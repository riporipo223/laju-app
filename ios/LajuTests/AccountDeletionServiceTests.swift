import CoreData
@testable import Laju
import XCTest

/// Thread-safe flags/counters for `@Sendable` closures (a bare captured `var` is a Swift 6 error).
private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var signOuts = 0
    private var notificationClears = 0
    private var request: URLRequest?

    func noteSignOut() {
        lock.lock()
        signOuts += 1
        lock.unlock()
    }

    func noteNotificationClear() {
        lock.lock()
        notificationClears += 1
        lock.unlock()
    }

    func capture(_ request: URLRequest) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    var signOutCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return signOuts
    }

    var notificationClearCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return notificationClears
    }

    var capturedRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

@MainActor
final class AccountDeletionServiceTests: XCTestCase {
    private let suite = "laju.tests.account-deletion"

    private func makeDefaults() -> UserDefaults {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(false, forKey: "audioCuesEnabled")
        return defaults
    }

    private func seedLocalData(_ controller: PersistenceController) {
        let context = controller.container.viewContext
        for index in 0 ..< 2 {
            let run = Run(context: context)
            run.id = UUID()
            run.startedAt = Date().addingTimeInterval(Double(-index) * 3600)
            run.syncStatus = index == 0 ? "pendingSync" : "synced" // one still queued for upload
            run.gpsRoute = Data("precise-location-history".utf8)
        }
        let meta = controller.syncMeta(in: context)
        meta.lastReconciledAt = Date()
        try? context.save()
    }

    private func count(_ entity: String, in controller: PersistenceController) throws -> Int {
        try controller.container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: entity))
    }

    private func makeService(
        _ controller: PersistenceController,
        defaults: UserDefaults,
        probe: Probe,
        jwt: @escaping @Sendable () async throws -> String = { "jwt" },
        signOut: @escaping @Sendable () async throws -> Void = {},
        onDeleted: @escaping @MainActor () -> Void = {}
    ) -> AccountDeletionService {
        AccountDeletionService(
            persistence: controller,
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: jwt,
            signOutLocally: {
                probe.noteSignOut()
                try await signOut()
            },
            defaults: defaults,
            defaultsDomain: suite,
            clearPendingNotifications: { probe.noteNotificationClear() },
            onDeleted: onDeleted
        )
    }

    // MARK: - DoD: local Core Data, Keychain session, UserDefaults cleared on successful deletion

    func testSuccessfulDeletionWipesEveryLocalStore() async throws {
        let controller = PersistenceController(inMemory: true)
        seedLocalData(controller)
        let defaults = makeDefaults()
        let probe = Probe()
        StubURLProtocol.requestHandler = { request in
            probe.capture(request)
            return (200, Data(#"{"deleted":true}"#.utf8))
        }
        var deletedCallbackFired = false
        let service = makeService(
            controller,
            defaults: defaults,
            probe: probe,
            onDeleted: { deletedCallbackFired = true }
        )
        XCTAssertEqual(try count("Run", in: controller), 2)

        let deleted = await service.deleteAccount()

        XCTAssertTrue(deleted)
        XCTAssertEqual(try count("Run", in: controller), 0, "all local runs (incl. precise routes) must be gone")
        XCTAssertEqual(try count("SyncMeta", in: controller), 0)
        XCTAssertNil(defaults.object(forKey: "hasCompletedOnboarding"), "UserDefaults must be cleared")
        XCTAssertNil(defaults.object(forKey: "audioCuesEnabled"))
        XCTAssertEqual(probe.signOutCount, 1, "the local (Keychain) session must be dropped")
        XCTAssertEqual(probe.notificationClearCount, 1)
        XCTAssertTrue(deletedCallbackFired, "in-memory view models must get to drop the deleted user's data")

        let request = try XCTUnwrap(probe.capturedRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
    }

    func testFreshSignUpOnTheSameDeviceFindsNothingToUploadUnderTheNewIdentity() async throws {
        let controller = PersistenceController(inMemory: true)
        seedLocalData(controller) // includes a run still `pendingSync`
        StubURLProtocol.requestHandler = { _ in (200, Data()) }
        let service = makeService(controller, defaults: makeDefaults(), probe: Probe())

        await service.deleteAccount()

        // The exact query `SyncService.syncPendingRuns` uses to decide what to upload.
        let request = Run.fetchRequest()
        request.predicate = NSPredicate(format: "syncStatus == %@ AND endedAt != nil", "pendingSync")
        XCTAssertEqual(try controller.container.viewContext.fetch(request).count, 0)
        XCTAssertEqual(try count("Run", in: controller), 0)
    }

    // MARK: - Server first: a failed deletion touches nothing local

    func testServerFailureLeavesAllLocalDataAndSessionUntouched() async throws {
        let controller = PersistenceController(inMemory: true)
        seedLocalData(controller)
        let defaults = makeDefaults()
        let probe = Probe()
        StubURLProtocol.requestHandler = { _ in (500, Data(#"{"error":"boom"}"#.utf8)) }
        let service = makeService(controller, defaults: defaults, probe: probe)

        let deleted = await service.deleteAccount()

        XCTAssertFalse(deleted)
        XCTAssertTrue(service.lastAttemptFailed)
        XCTAssertEqual(try count("Run", in: controller), 2, "a failed deletion must not cost the user their data")
        XCTAssertEqual(try count("SyncMeta", in: controller), 1)
        XCTAssertEqual(defaults.bool(forKey: "hasCompletedOnboarding"), true)
        XCTAssertEqual(probe.signOutCount, 0, "must stay signed in so the user can retry")
        XCTAssertEqual(probe.notificationClearCount, 0)
    }

    func testNetworkFailureAlsoLeavesEverythingAndARetryThenSucceeds() async throws {
        let controller = PersistenceController(inMemory: true)
        seedLocalData(controller)
        let defaults = makeDefaults()
        let service = makeService(controller, defaults: defaults, probe: Probe())

        StubURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let first = await service.deleteAccount()
        XCTAssertFalse(first)
        XCTAssertEqual(try count("Run", in: controller), 2)

        StubURLProtocol.requestHandler = { _ in (200, Data()) }
        let second = await service.deleteAccount()
        XCTAssertTrue(second)
        XCTAssertFalse(service.lastAttemptFailed, "a new attempt clears the failure flag")
        XCTAssertEqual(try count("Run", in: controller), 0)
    }

    func testSignedOutCannotDeleteAndTouchesNothing() async throws {
        let controller = PersistenceController(inMemory: true)
        seedLocalData(controller)
        StubURLProtocol.requestHandler = { _ in
            XCTFail("no session — must not reach the network")
            return (200, Data())
        }
        let service = makeService(
            controller,
            defaults: makeDefaults(),
            probe: Probe(),
            jwt: { throw APIClientError.notAuthenticated }
        )

        let deleted = await service.deleteAccount()

        XCTAssertFalse(deleted)
        XCTAssertEqual(try count("Run", in: controller), 2)
    }

    func testLocalSignOutHiccupDoesNotTurnADeletedAccountIntoAFailure() async throws {
        let controller = PersistenceController(inMemory: true)
        seedLocalData(controller)
        StubURLProtocol.requestHandler = { _ in (200, Data()) }
        let service = makeService(
            controller,
            defaults: makeDefaults(),
            probe: Probe(),
            signOut: { throw URLError(.cannotConnectToHost) }
        )

        let deleted = await service.deleteAccount()

        XCTAssertTrue(deleted, "the server account is already gone — the user must be told it worked")
        XCTAssertEqual(try count("Run", in: controller), 0)
    }

    // MARK: - In-memory state

    func testProgressViewModelResetDropsTheDeletedUsersCachedValues() async {
        StubURLProtocol.requestHandler = { _ in
            (200, Data(#"{"total_points":900,"current_level":4,"points_to_next_level":600,"trust_score":1.0}"#.utf8))
        }
        let viewModel = ProgressViewModel(
            apiClient: APIClient(session: StubURLProtocol.makeSession()),
            currentJWT: { "jwt" }
        )
        await viewModel.refresh()
        XCTAssertNotNil(viewModel.serverProgress)

        viewModel.reset()

        XCTAssertNil(viewModel.serverProgress)
    }
}
