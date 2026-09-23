@testable import Laju
import XCTest

/// The onboarding profile step: what the app sends to `POST /api/profile/complete`, when it decides a profile is
/// missing, and how failures read. Reuses `StubURLProtocol` from `SyncServiceTests.swift`.
@MainActor
final class ProfileSetupTests: XCTestCase {
    private func makeModel(token: @escaping @Sendable () async throws -> String = { "test-jwt" })
        -> ProfileSetupViewModel {
        StubURLProtocol.requestHandler = nil
        return ProfileSetupViewModel(apiClient: APIClient(session: StubURLProtocol.makeSession()), accessToken: token)
    }

    private func fillValid(_ model: ProfileSetupViewModel) {
        model.username = "  andi_r9 "
    }

    // MARK: - Validation

    /// Region fields were removed 2026-09-22 (D1 reversed) — username is now the only thing gating submit.
    func testNothingCanBeSubmittedUntilTheUsernameIsValid() {
        let model = makeModel()
        XCTAssertNil(model.request)
        XCTAssertFalse(model.canSubmit)
        model.username = "   "
        XCTAssertNil(model.request, "whitespace is not a value")
        model.username = "ab"
        XCTAssertNil(model.request, "too short")
        model.username = "andi_r9"
        XCTAssertTrue(model.canSubmit)
    }

    func testUsernameRules() {
        XCTAssertTrue(ProfileSetupViewModel.isValidUsername("abc"))
        XCTAssertTrue(ProfileSetupViewModel.isValidUsername("andi_r9"))
        XCTAssertTrue(ProfileSetupViewModel.isValidUsername(String(repeating: "a", count: 24)))
        XCTAssertFalse(ProfileSetupViewModel.isValidUsername("ab"), "too short")
        XCTAssertFalse(ProfileSetupViewModel.isValidUsername(String(repeating: "a", count: 25)), "too long")
        XCTAssertFalse(ProfileSetupViewModel.isValidUsername("andi r"), "no spaces")
        XCTAssertFalse(ProfileSetupViewModel.isValidUsername("andi-r"), "no hyphen")
        XCTAssertFalse(ProfileSetupViewModel.isValidUsername("andí"), "ASCII only")
    }

    func testRequestIsTrimmed() throws {
        let model = makeModel()
        fillValid(model)
        let request = try XCTUnwrap(model.request)
        XCTAssertEqual(request.username, "andi_r9")
    }

    // MARK: - What is sent

    func testSubmitPostsTheDocumentedBodyWithTheBearerToken() async throws {
        let model = makeModel()
        fillValid(model)
        let seen = Seen()
        StubURLProtocol.requestHandler = { request in
            seen.record(request)
            return (201, Data(#"{"id":"u1","username":"andi_r9","total_points":0,"current_level":1}"#.utf8))
        }

        let ok = await model.submit()

        XCTAssertTrue(ok)
        XCTAssertEqual(model.state, .idle)
        let request = try XCTUnwrap(seen.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/profile/complete")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-jwt")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(seen.body)) as? [String: String])
        // Region keys must be ABSENT, not empty — the client stopped collecting them entirely
        // (2026-09-22, D1 reversed). Asserting the whole dictionary keeps this honest: an accidental
        // re-introduction of any region key fails here.
        XCTAssertEqual(body, ["username": "andi_r9"])
    }

    func testSubmitWithAnIncompleteFormSendsNothing() async {
        let model = makeModel()
        StubURLProtocol.requestHandler = { _ in
            XCTFail("an invalid form must not reach the network")
            return (201, Data())
        }
        let ok = await model.submit()
        XCTAssertFalse(ok)
        XCTAssertEqual(model.state, .idle)
    }

    // MARK: - Failures read as something a user can act on

    func testServerAndNetworkFailuresBecomeMessagesAndStayEditable() async {
        let cases: [(Int, String)] = [
            (400, "tidak valid"), (401, "Sesi masuk berakhir"), (429, "Terlalu banyak"), (500, "Gagal menyimpan")
        ]
        for (status, fragment) in cases {
            let model = makeModel()
            fillValid(model)
            StubURLProtocol.requestHandler = { _ in (status, Data(#"{"error":"x"}"#.utf8)) }
            let ok = await model.submit()
            XCTAssertFalse(ok, "HTTP \(status)")
            guard case let .failed(message) = model.state else { return XCTFail("HTTP \(status) must leave a message") }
            XCTAssertTrue(message.contains(fragment), "HTTP \(status): \(message)")
            XCTAssertTrue(model.canSubmit, "the form stays editable and re-submittable after HTTP \(status)")
        }
    }

    func testNoConnectionHasItsOwnMessage() async {
        let model = makeModel()
        fillValid(model)
        StubURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let ok = await model.submit()
        XCTAssertFalse(ok)
        XCTAssertEqual(model.state, .failed("Tidak ada koneksi. Coba lagi saat online."))
    }

    func testMissingSessionIsReportedNotCrashed() async {
        let model = makeModel(token: { throw APIClientError.notAuthenticated })
        fillValid(model)
        let ok = await model.submit()
        XCTAssertFalse(ok)
        if case .failed = model.state {} else {
            XCTFail("no token must surface as a failure")
        }
    }

    // MARK: - Deciding whether the step is needed

    func testAProfileThatExistsMeansSkipTheStep() async throws {
        StubURLProtocol.requestHandler = { _ in (200, Data(#"{"id":"u1","auth_user_id":"a1"}"#.utf8)) }
        let hasProfile = try await APIClient(session: StubURLProtocol.makeSession()).hasProfile(jwt: "t")
        XCTAssertTrue(hasProfile)
    }

    func testTheProfileMissingCodeMeansShowTheStep() async throws {
        StubURLProtocol.requestHandler = { _ in
            (401, Data(#"{"error":"No user profile exists for this identity","code":"profile_missing"}"#.utf8))
        }
        let hasProfile = try await APIClient(session: StubURLProtocol.makeSession()).hasProfile(jwt: "t")
        XCTAssertFalse(hasProfile)
    }

    func testAnyOther401IsABrokenSessionNotAMissingProfile() async {
        StubURLProtocol.requestHandler = { _ in (401, Data(#"{"error":"Invalid or expired token"}"#.utf8)) }
        do {
            _ = try await APIClient(session: StubURLProtocol.makeSession()).hasProfile(jwt: "t")
            XCTFail("a bad token is not 'no profile'")
        } catch {
            XCTAssertEqual(
                error as? APIClientError,
                .server(statusCode: 401, body: #"{"error":"Invalid or expired token"}"#)
            )
        }
    }

    func testAServerErrorIsAnErrorNotAMissingProfile() async {
        StubURLProtocol.requestHandler = { _ in (500, Data()) }
        do {
            _ = try await APIClient(session: StubURLProtocol.makeSession()).hasProfile(jwt: "t")
            XCTFail("a 5xx must not read as 'no profile'")
        } catch {
            XCTAssertEqual(error as? APIClientError, .server(statusCode: 500, body: ""))
        }
    }
}

/// Captures the request the stub saw. A `URLProtocol` receives the body as a stream, not `httpBody`, so it is read
/// here.
private final class Seen: @unchecked Sendable {
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
                if read <= 0 {
                    break
                }
                data.append(buffer, count: read)
            }
            return data
        }
    }
}
