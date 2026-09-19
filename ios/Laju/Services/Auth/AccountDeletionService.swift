import CoreData
import Foundation
import UserNotifications

/// T2.22 (App Store Guideline 5.1.1(v), product-spec.md §4.17): in-app account deletion.
///
/// **Server first, local wipe only after it succeeds.** If `DELETE /api/account` fails, nothing local is
/// touched — the user still has their data, still holds a working session, and can simply retry. Wiping
/// first would leave a user with no data and no working session whose server account still exists.
///
/// After a successful server deletion the device must not keep the deleted user's data (database-api-spec.md
/// §2.1b point 4): without this the precise-location history stays on the phone in cleartext, and a fresh
/// sign-up on the same device would find the old runs still `pendingSync` and upload them under the new
/// identity. So this clears every local store the app owns: Core Data (`Run`, `SyncMeta`), the Keychain-backed
/// Supabase session, `UserDefaults`, and pending local notifications.
@MainActor
final class AccountDeletionService: ObservableObject {
    @Published private(set) var isDeleting = false
    /// Set when the server-side deletion failed; cleared at the start of the next attempt.
    @Published private(set) var lastAttemptFailed = false

    private let persistence: PersistenceController
    private let apiClient: APIClient
    private let currentJWT: @Sendable () async throws -> String
    /// Local sign-out only: the server already deleted the identity, so a network sign-out would just fail.
    private let signOutLocally: @Sendable () async throws -> Void
    private let defaults: UserDefaults
    private let defaultsDomain: String
    private let clearPendingNotifications: @Sendable () -> Void
    /// Lets in-memory view models drop the deleted user's data too (e.g. `ProgressViewModel.reset()`).
    private let onDeleted: @MainActor () -> Void

    init(
        persistence: PersistenceController,
        apiClient: APIClient = APIClient(),
        currentJWT: @escaping @Sendable () async throws -> String = {
            try await SupabaseConfig.client.auth.session.accessToken
        },
        signOutLocally: @escaping @Sendable () async throws -> Void = {
            try await SupabaseConfig.client.auth.signOut(scope: .local)
        },
        defaults: UserDefaults = .standard,
        defaultsDomain: String = Bundle.main.bundleIdentifier ?? "",
        clearPendingNotifications: @escaping @Sendable () -> Void = {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        },
        onDeleted: @escaping @MainActor () -> Void = {}
    ) {
        self.persistence = persistence
        self.apiClient = apiClient
        self.currentJWT = currentJWT
        self.signOutLocally = signOutLocally
        self.defaults = defaults
        self.defaultsDomain = defaultsDomain
        self.clearPendingNotifications = clearPendingNotifications
        self.onDeleted = onDeleted
    }

    /// Returns `true` once the account is deleted on the server (the local wipe is best-effort from there:
    /// the account is already gone, so a local hiccup must not be reported as a failed deletion).
    @discardableResult
    func deleteAccount() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        lastAttemptFailed = false
        defer { isDeleting = false }

        do {
            let jwt = try await currentJWT()
            try await apiClient.deleteAccount(jwt: jwt)
        } catch {
            lastAttemptFailed = true
            return false
        }

        wipeCoreData()
        try? await signOutLocally()
        if !defaultsDomain.isEmpty {
            defaults.removePersistentDomain(forName: defaultsDomain)
        }
        clearPendingNotifications()
        onDeleted()
        return true
    }

    private func wipeCoreData() {
        let context = persistence.container.viewContext
        for entity in ["Run", "SyncMeta"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            for object in (try? context.fetch(request)) ?? [] {
                context.delete(object)
            }
        }
        try? context.save()
    }
}
