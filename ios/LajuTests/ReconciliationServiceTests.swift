import CoreData
@testable import Laju
import XCTest

/// Thread-safe recorder/counter for `@Sendable` stub closures (a bare captured `var` is a Swift 6 error).
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var sinces: [String?] = []
    private var refreshCount = 0
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    func recordSince(from request: URLRequest) {
        let since = request.url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first(where: { $0.name == "since" })?.value
        lock.lock()
        sinces.append(since)
        lock.unlock()
    }

    var recordedSinces: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return sinces
    }

    func noteRefresh() {
        lock.lock()
        refreshCount += 1
        lock.unlock()
    }

    var refreshes: Int {
        lock.lock()
        defer { lock.unlock() }
        return refreshCount
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return clock
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        clock = clock.addingTimeInterval(seconds)
        lock.unlock()
    }
}

@MainActor
final class ReconciliationServiceTests: XCTestCase {
    private func makeController() -> PersistenceController {
        StubURLProtocol.requestHandler = nil
        return PersistenceController(inMemory: true)
    }

    @discardableResult
    private func seedRun(
        _ controller: PersistenceController,
        serverRunId: String = "srv-1",
        serverStatus: String? = "flagged",
        syncStatus: String = "synced"
    ) -> Run {
        let run = Run(context: controller.container.viewContext)
        run.id = UUID()
        run.startedAt = Date()
        run.syncStatus = syncStatus
        run.serverRunId = serverRunId
        run.serverStatus = serverStatus
        run.finalPointsAwarded = NSNumber(value: 2)
        try? controller.container.viewContext.save()
        return run
    }

    private func makeService(
        _ controller: PersistenceController,
        recorder: Recorder,
        jwt: @escaping @Sendable () async throws -> String = { "test-jwt" }
    ) -> ReconciliationService {
        ReconciliationService(
            persistence: controller,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: jwt,
            onRunsChanged: { recorder.noteRefresh() },
            now: { recorder.now }
        )
    }

    private nonisolated static func runJSON(
        runId: String,
        status: String = "approved",
        points: Int = 7,
        updatedAt: String = "2026-09-18T10:00:00.000Z"
    ) -> String {
        """
        {"run_id":"\(runId)","status":"\(status)","flag_confidence":"low","final_points_awarded":\(points),
        "resolved_at":"2026-09-18T10:00:00.000Z","updated_at":"\(updatedAt)","anomaly_flags":["pace_cap_exceeded"]}
        """
    }

    private nonisolated static func body(
        runs: [String],
        hasMore: Bool = false,
        serverTime: String = "2026-09-18T11:00:00.000Z"
    ) -> Data {
        Data("""
        {"server_time":"\(serverTime)","has_more":\(hasMore),"runs":[\(runs.joined(separator: ","))]}
        """.utf8)
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso) ?? Date.distantPast
    }

    // MARK: - DoD: skips entirely with zero locally-flagged runs

    func testSkipsCallEntirelyWhenNoFlaggedRun() async {
        let controller = makeController()
        seedRun(controller, serverStatus: "validated")
        let recorder = Recorder()
        StubURLProtocol.requestHandler = { request in
            recorder.recordSince(from: request)
            return (200, Self.body(runs: []))
        }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()

        XCTAssertTrue(recorder.recordedSinces.isEmpty, "no flagged run — must not call the endpoint")
        XCTAssertNil(controller.syncMeta(in: controller.container.viewContext).lastReconcileAttemptAt)
    }

    // MARK: - DoD: 15-minute floor, including across a restart (persisted timestamp, not in-memory state)

    func testFifteenMinuteFloorSurvivesRestart() async {
        let controller = makeController()
        seedRun(controller)
        let recorder = Recorder()
        StubURLProtocol.requestHandler = { request in
            recorder.recordSince(from: request)
            return (200, Self.body(runs: []))
        }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()
        XCTAssertEqual(recorder.recordedSinces.count, 1)

        // "Restart": a brand-new service instance — only the persisted SyncMeta carries state over.
        recorder.advance(by: 14 * 60)
        await makeService(controller, recorder: recorder).reconcileIfNeeded()
        XCTAssertEqual(recorder.recordedSinces.count, 1, "14 min after the last attempt is inside the floor")

        recorder.advance(by: 2 * 60)
        await makeService(controller, recorder: recorder).reconcileIfNeeded()
        XCTAssertEqual(recorder.recordedSinces.count, 2, "16 min after the last attempt is past the floor")
    }

    // MARK: - DoD: first call omits since; later calls send the server-issued cursor, never a device time

    func testFirstCallOmitsSinceAndNextCallUsesServerTimeDespiteSkewedClock() async {
        let controller = makeController()
        seedRun(controller)
        let recorder = Recorder()
        StubURLProtocol.requestHandler = { request in
            recorder.recordSince(from: request)
            return (200, Self.body(runs: [], serverTime: "2026-09-18T11:00:00.000Z"))
        }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()
        // Deliberately skewed device clock: a decade ahead. The cursor must still be the server's.
        recorder.advance(by: 10 * 365 * 24 * 3600)
        await makeService(controller, recorder: recorder).reconcileIfNeeded()

        XCTAssertEqual(recorder.recordedSinces.count, 2)
        XCTAssertNil(recorder.recordedSinces[0] ?? nil, "first-ever call must omit since")
        XCTAssertEqual(recorder.recordedSinces[1], "2026-09-18T11:00:00.000Z", "must send server_time, not device time")
    }

    // MARK: - DoD: has_more drained via immediate follow-ups, cursor = last row's updated_at until drained

    func testHasMoreIsDrainedWithLastRowCursorThenServerTime() async {
        let controller = makeController()
        seedRun(controller)
        let recorder = Recorder()
        StubURLProtocol.requestHandler = { request in
            recorder.recordSince(from: request)
            if recorder.recordedSinces.count == 1 {
                let rows = [
                    Self.runJSON(runId: "x1", updatedAt: "2026-09-18T10:00:01.000Z"),
                    Self.runJSON(runId: "x2", updatedAt: "2026-09-18T10:00:02.000Z")
                ]
                return (200, Self.body(runs: rows, hasMore: true, serverTime: "2026-09-18T12:00:00.000Z"))
            }
            return (200, Self.body(runs: [], serverTime: "2026-09-18T12:00:05.000Z"))
        }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()

        XCTAssertEqual(recorder.recordedSinces.count, 2, "has_more must trigger an immediate follow-up in one cycle")
        XCTAssertEqual(recorder.recordedSinces[1], "2026-09-18T10:00:02.000Z", "cursor while draining = last row")
        let meta = controller.syncMeta(in: controller.container.viewContext)
        XCTAssertEqual(meta.lastReconciledAt, date("2026-09-18T12:00:05.000Z"), "drained → server_time")
    }

    // MARK: - DoD: ≥200 rows sharing one updated_at must terminate, not loop forever

    func testIdenticalUpdatedAtBatchTerminatesTheDrainLoop() async {
        let controller = makeController()
        seedRun(controller)
        let recorder = Recorder()
        StubURLProtocol.requestHandler = { request in
            recorder.recordSince(from: request)
            let rows = (0 ..< 200).map { Self.runJSON(runId: "same-\($0)", updatedAt: "2026-09-18T10:00:00.000Z") }
            return (200, Self.body(runs: rows, hasMore: true))
        }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()

        XCTAssertEqual(recorder.recordedSinces.count, 2, "second call returns nothing newer than the cursor → stop")
    }

    // MARK: - DoD: flagged → approved is mirrored locally AND triggers the progress refresh

    func testResolutionUpdatesLocalRowAndTriggersProgressRefresh() async {
        let controller = makeController()
        let run = seedRun(controller)
        let recorder = Recorder()
        StubURLProtocol.requestHandler = { _ in
            (200, Self.body(runs: [Self.runJSON(runId: "srv-1", status: "approved", points: 7)]))
        }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()

        XCTAssertEqual(run.serverStatus, "approved")
        XCTAssertEqual(run.finalPointsAwarded, 7)
        XCTAssertEqual(run.flagConfidence, "low")
        XCTAssertEqual(run.resolvedAt, date("2026-09-18T10:00:00.000Z"))
        let flags = (try? JSONDecoder().decode([String].self, from: run.anomalyFlags ?? Data())) ?? []
        XCTAssertEqual(flags, ["pace_cap_exceeded"])
        XCTAssertEqual(recorder.refreshes, 1, "a Core Data save alone is not enough — refresh() must be triggered")
    }

    func testUnchangedStatusDoesNotTriggerRefresh() async {
        let controller = makeController()
        seedRun(controller) // flagged, 2 points
        let recorder = Recorder()
        StubURLProtocol.requestHandler = { _ in
            (200, Self.body(runs: [Self.runJSON(runId: "srv-1", status: "flagged", points: 2)]))
        }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()

        XCTAssertEqual(recorder.refreshes, 0)
    }

    // MARK: - DoD: unmatched run_id ignored, never inserted

    func testUnmatchedRunIdIsIgnoredNotInserted() async throws {
        let controller = makeController()
        seedRun(controller)
        let recorder = Recorder()
        StubURLProtocol.requestHandler = { _ in
            (200, Self.body(runs: [Self.runJSON(runId: "someone-elses-run")]))
        }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()

        let count = try controller.container.viewContext.count(for: Run.fetchRequest())
        XCTAssertEqual(count, 1)
        XCTAssertEqual(recorder.refreshes, 0)
    }

    // MARK: - DoD: failure updates attempt timestamp only, never touches the upload-retry queue

    func testFailureStoresAttemptButNotCursorAndLeavesUploadQueueAlone() async {
        let controller = makeController()
        seedRun(controller)
        let pending = seedRun(controller, serverRunId: "pending-1", serverStatus: nil, syncStatus: "pendingSync")
        let recorder = Recorder()
        StubURLProtocol.requestHandler = { _ in (500, Data(#"{"error":"boom"}"#.utf8)) }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()

        let meta = controller.syncMeta(in: controller.container.viewContext)
        XCTAssertEqual(meta.lastReconcileAttemptAt, recorder.now, "attempt recorded on failure")
        XCTAssertNil(meta.lastReconciledAt, "failure must not advance the cursor")
        XCTAssertEqual(pending.syncStatus, "pendingSync", "T2.14's upload queue is untouched")
        XCTAssertEqual(recorder.refreshes, 0)
    }

    func testSignedOutIsNotAnAttempt() async {
        let controller = makeController()
        seedRun(controller)
        let recorder = Recorder()
        StubURLProtocol.requestHandler = { _ in
            XCTFail("no session — must not reach the network")
            return (200, Data())
        }

        await makeService(controller, recorder: recorder, jwt: { throw APIClientError.notAuthenticated })
            .reconcileIfNeeded()

        XCTAssertNil(controller.syncMeta(in: controller.container.viewContext).lastReconcileAttemptAt)
    }

    // MARK: - Real server emits microseconds (PostgREST), which ISO8601DateFormatter alone rejects

    func testMicrosecondTimestampsFromPostgRESTDecode() async {
        let controller = makeController()
        let run = seedRun(controller)
        let recorder = Recorder()
        let row = """
        {"run_id":"srv-1","status":"approved","flag_confidence":"low","final_points_awarded":7,
        "resolved_at":"2026-09-18T10:00:00.123456+00:00","updated_at":"2026-09-18T10:00:00.123456+00:00",
        "anomaly_flags":[]}
        """
        StubURLProtocol.requestHandler = { _ in (200, Self.body(runs: [row])) }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()

        XCTAssertEqual(run.serverStatus, "approved", "a microsecond timestamp must not make the response fail")
        XCTAssertEqual(run.resolvedAt, date("2026-09-18T10:00:00.123Z"))
    }

    // MARK: - Live server can return final_points_awarded: null — must not fail the whole page

    func testNullFinalPointsDoesNotFailDecodingAndKeepsLocalValue() async {
        let controller = makeController()
        let run = seedRun(controller) // 2 points locally
        let recorder = Recorder()
        let row = """
        {"run_id":"srv-1","status":"flagged","flag_confidence":"low","final_points_awarded":null,
        "resolved_at":null,"updated_at":"2026-09-18T19:45:59.395546+00:00","anomaly_flags":["pace_cap_exceeded"]}
        """
        StubURLProtocol.requestHandler = { _ in (200, Self.body(runs: [row])) }

        await makeService(controller, recorder: recorder).reconcileIfNeeded()

        XCTAssertEqual(run.finalPointsAwarded, 2, "a null must not wipe a known local value")
        XCTAssertNotNil(controller.syncMeta(in: controller.container.viewContext).lastReconciledAt)
    }
}
