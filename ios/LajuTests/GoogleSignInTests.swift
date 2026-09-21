import AuthenticationServices
@testable import Laju
import XCTest

/// The OAuth round-trip itself needs a browser and a Google account, so it is verified by hand (see the T2.3 notes).
/// What can be pinned without one: the redirect URL that Supabase's allow-list must contain, and which errors count as
/// "the user closed the sheet" — for BOTH providers, since they share one handler.
final class GoogleSignInTests: XCTestCase {
    func testRedirectURLMatchesTheSupabaseAllowListEntry() {
        XCTAssertEqual(AuthService.oauthRedirectURL.absoluteString, "com.designbyripo.laju://auth-callback")
        XCTAssertEqual(AuthService.oauthRedirectURL.scheme, "com.designbyripo.laju")
    }

    func testClosingTheGoogleBrowserSheetIsACancellationNotAnError() {
        let error = NSError(
            domain: ASWebAuthenticationSessionError.errorDomain,
            code: ASWebAuthenticationSessionError.canceledLogin.rawValue
        )
        XCTAssertTrue(AuthService.isUserCancellation(error))
    }

    func testCancellingSignInWithAppleIsStillACancellation() {
        let error = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.canceled.rawValue)
        XCTAssertTrue(AuthService.isUserCancellation(error))
    }

    func testRealFailuresAreNotSwallowed() {
        let notCancel = NSError(
            domain: ASWebAuthenticationSessionError.errorDomain,
            code: ASWebAuthenticationSessionError.presentationContextNotProvided.rawValue
        )
        XCTAssertFalse(AuthService.isUserCancellation(notCancel))
        let appleFailure = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.failed.rawValue)
        XCTAssertFalse(AuthService.isUserCancellation(appleFailure))
        XCTAssertFalse(AuthService.isUserCancellation(URLError(.notConnectedToInternet)))
    }
}
