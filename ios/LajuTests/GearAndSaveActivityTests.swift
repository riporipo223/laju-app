@testable import Laju
import CoreData
import XCTest

/// Same shape as `SocialFeedTests.swift`'s private request-recording box (that one is `private` to its own
/// file, so this file needs its own copy rather than reaching across.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?
    private var storedBody: Data?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    var body: Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedBody
    }

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequest = request
        storedBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }
    }
}

/// A `@Sendable` flag, for asserting a stub handler was/wasn't invoked from a `StubURLProtocol.requestHandler`
/// closure (which runs off the test's own executor, so a plain captured `var` isn't allowed under strict
/// concurrency).
private final class CallFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func markCalled() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }

    var wasCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// T4.21: gear DTO decoding/encoding, `GearViewModel`'s CRUD calls, and `PendingPostPublisher`'s
/// deferred-publish gate. Reuses `StubURLProtocol` from `SyncServiceTests.swift`, same pattern
/// `SocialFeedTests.swift` documents for T4.15.
@MainActor
final class GearAndSaveActivityTests: XCTestCase {
    // MARK: - Gear DTO

    func testDecodesGearListShape() throws {
        let json = """
        {"gear":[{"gear_id":"g1","brand":"Nike","model":"AirMax 95","size":"42",
        "created_at":"2026-09-25T10:00:00.000000+00:00"}]}
        """
        let decoded = try RunSubmissionCoding.makeDecoder().decode(GearListResponse.self, from: Data(json.utf8))
        let gear = try XCTUnwrap(decoded.gear.first)
        XCTAssertEqual(gear.brand, "Nike")
        XCTAssertEqual(gear.displayName, "Nike AirMax 95")
    }

    func testGearDisplayNameFallsBackToBrandOnlyWhenModelIsNil() throws {
        let json = """
        {"gear_id":"g1","brand":"Hoka","model":null,"size":null,
        "created_at":"2026-09-25T10:00:00.000000+00:00"}
        """
        let decoded = try RunSubmissionCoding.makeDecoder().decode(Gear.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.displayName, "Hoka")
    }

    // MARK: - CreateSocialPostRequest carries T4.21's new fields

    func testCreateSocialPostRequestEncodesAllT421Fields() async throws {
        let box = RequestBox()
        StubURLProtocol.requestHandler = { request in
            box.record(request)
            return (
                201,
                Data(
                    #"""
                    {"post_id":"p1","run_id":"r1","caption":null,"title":"Sunday long run",
                    "description":"Felt great","map_type":"activity_heat","visibility":"private",
                    "gear_id":"g1","created_at":"2026-09-25T10:00:00Z"}
                    """#.utf8
                )
            )
        }
        let client = APIClient(session: StubURLProtocol.makeSession())
        _ = try await client.createSocialPost(
            runId: "r1",
            caption: nil,
            title: "Sunday long run",
            description: "Felt great",
            privateNotes: "knee twinge",
            mapType: "activity_heat",
            visibility: "private",
            gearId: "g1",
            jwt: "jwt-1"
        )

        let body = try XCTUnwrap(box.body)
        let decodedBody = try JSONDecoder().decode(CreateSocialPostRequest.self, from: body)
        XCTAssertEqual(decodedBody.title, "Sunday long run")
        XCTAssertEqual(decodedBody.mapType, "activity_heat")
        XCTAssertEqual(decodedBody.visibility, "private")
        XCTAssertEqual(decodedBody.gearId, "g1")
        XCTAssertEqual(decodedBody.privateNotes, "knee twinge")
    }

    // MARK: - GearViewModel

    func testGearViewModelLoadPopulatesGearFromTheServer() async throws {
        StubURLProtocol.requestHandler = { _ in
            (200, Data(#"{"gear":[{"gear_id":"g1","brand":"Nike","model":null,"size":null,"created_at":"2026-09-25T10:00:00Z"}]}"#.utf8))
        }
        let model = GearViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        await model.load()
        XCTAssertEqual(model.gear.count, 1)
        XCTAssertEqual(model.gear.first?.brand, "Nike")
    }

    func testGearViewModelAddGearAppendsOnSuccess() async throws {
        StubURLProtocol.requestHandler = { _ in
            (201, Data(#"{"gear_id":"g2","brand":"Hoka","model":"Clifton","size":"43","created_at":"2026-09-25T10:00:00Z"}"#.utf8))
        }
        let model = GearViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        let created = await model.addGear(brand: "Hoka", model: "Clifton", size: "43")
        XCTAssertEqual(created?.gearId, "g2")
        XCTAssertEqual(model.gear.count, 1)
    }

    func testGearViewModelAddGearSetsErrorMessageOnFailure() async throws {
        StubURLProtocol.requestHandler = { _ in (400, Data(#"{"error":"brand must be one of: ..."}"#.utf8)) }
        let model = GearViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), currentJWT: { "jwt-1" })
        let created = await model.addGear(brand: "NotReal", model: nil, size: nil)
        XCTAssertNil(created)
        XCTAssertTrue(model.gear.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    // MARK: - PendingPostPublisher

    private func makeInMemoryContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    private func makeRun(in context: NSManagedObjectContext) -> Run {
        let run = Run(context: context)
        run.id = UUID()
        run.startedAt = Date()
        try? context.save()
        return run
    }

    func testPublishIfNeededSkipsWhenNoPostWasRequested() async throws {
        let context = makeInMemoryContext()
        let run = makeRun(in: context)
        run.pendingPostRequested = false
        run.serverRunId = "server-run-1"
        run.serverStatus = "validated"

        let called = CallFlag()
        StubURLProtocol.requestHandler = { _ in
            called.markCalled()
            return (201, Data("{}".utf8))
        }
        await PendingPostPublisher.publishIfNeeded(
            for: run,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            jwt: "jwt-1"
        )
        XCTAssertFalse(called.wasCalled)
        XCTAssertFalse(run.pendingPostPublished)
    }

    func testPublishIfNeededSkipsWhenStatusIsNotYetValidatedOrApproved() async throws {
        let context = makeInMemoryContext()
        let run = makeRun(in: context)
        run.pendingPostRequested = true
        run.serverRunId = "server-run-1"
        run.serverStatus = "pending_review"

        let called = CallFlag()
        StubURLProtocol.requestHandler = { _ in
            called.markCalled()
            return (201, Data("{}".utf8))
        }
        await PendingPostPublisher.publishIfNeeded(
            for: run,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            jwt: "jwt-1"
        )
        XCTAssertFalse(called.wasCalled)
    }

    func testPublishIfNeededSkipsWhenAlreadyPublished() async throws {
        let context = makeInMemoryContext()
        let run = makeRun(in: context)
        run.pendingPostRequested = true
        run.pendingPostPublished = true
        run.serverRunId = "server-run-1"
        run.serverStatus = "validated"

        let called = CallFlag()
        StubURLProtocol.requestHandler = { _ in
            called.markCalled()
            return (201, Data("{}".utf8))
        }
        await PendingPostPublisher.publishIfNeeded(
            for: run,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            jwt: "jwt-1"
        )
        XCTAssertFalse(called.wasCalled)
    }

    func testPublishIfNeededPostsAndMarksPublishedWhenValidated() async throws {
        let context = makeInMemoryContext()
        let run = makeRun(in: context)
        run.pendingPostRequested = true
        run.pendingPostTitle = "Sunday long run"
        run.pendingPostMapType = "standard"
        run.pendingPostVisibility = "public"
        run.serverRunId = "server-run-1"
        run.serverStatus = "validated"

        let box = RequestBox()
        StubURLProtocol.requestHandler = { request in
            box.record(request)
            return (
                201,
                Data(#"{"post_id":"p1","run_id":"server-run-1","caption":null,"created_at":"2026-09-25T10:00:00Z"}"#.utf8)
            )
        }
        await PendingPostPublisher.publishIfNeeded(
            for: run,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            jwt: "jwt-1"
        )
        XCTAssertTrue(run.pendingPostPublished)
        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.url?.path, "/api/social/posts")
        let body = try XCTUnwrap(box.body)
        let decodedBody = try JSONDecoder().decode(CreateSocialPostRequest.self, from: body)
        XCTAssertEqual(decodedBody.runId, "server-run-1")
        XCTAssertEqual(decodedBody.title, "Sunday long run")
    }

    func testPublishIfNeededLeavesPublishedFalseOnServerFailure() async throws {
        let context = makeInMemoryContext()
        let run = makeRun(in: context)
        run.pendingPostRequested = true
        run.serverRunId = "server-run-1"
        run.serverStatus = "approved"

        StubURLProtocol.requestHandler = { _ in (500, Data(#"{"error":"db down"}"#.utf8)) }
        await PendingPostPublisher.publishIfNeeded(
            for: run,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            jwt: "jwt-1"
        )
        XCTAssertFalse(run.pendingPostPublished) // stays false — next sync/reconciliation pass retries
    }
}
