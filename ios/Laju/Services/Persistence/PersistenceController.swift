import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    /// Parsed exactly once per process and reused by every
    /// `PersistenceController` instance. Re-parsing `Laju.momd` on each
    /// `init` (the original bug: `NSPersistentContainer(name:)` re-derives
    /// a model each time) produces a distinct `NSManagedObjectModel`
    /// object per instance — Core Data's `+entity` resolution then sees
    /// multiple model objects claiming the same `Run`/`SyncMeta` classes
    /// and can't disambiguate, even though both came from the identical
    /// file. This bit when the test host app's own `.shared` and a test's
    /// `PersistenceController(inMemory: true)` both existed in the same
    /// process (found running LajuTests, T0.6 verification).
    /// `nonisolated(unsafe)`: `NSManagedObjectModel` is immutable once
    /// loaded and safe to share, but isn't `Sendable` so Swift 6 strict
    /// concurrency can't verify that itself — this documents the
    /// exception is deliberate, per the compiler's own suggested fix.
    private nonisolated(unsafe) static let model: NSManagedObjectModel = {
        guard
            let modelURL = Bundle(for: BundleToken.self).url(forResource: "Laju", withExtension: "momd"),
            let model = NSManagedObjectModel(contentsOf: modelURL)
        else {
            fatalError("Failed to locate Laju Core Data model")
        }
        return model
    }()

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Laju", managedObjectModel: Self.model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Unresolved Core Data error: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// `SyncMeta` is a single-instance entity — the reconciliation cursor
    /// and cadence anchor (tech-spec.md §3 step 7). Fetches the existing
    /// instance or creates it on first access.
    func syncMeta(in context: NSManagedObjectContext) -> SyncMeta {
        let request = SyncMeta.fetchRequest()
        request.fetchLimit = 1
        if let existing = try? context.fetch(request).first {
            return existing
        }
        let created = SyncMeta(context: context)
        try? context.save()
        return created
    }
}

/// Anchor type for `Bundle(for:)` — resolves to the app's own bundle
/// (where `Laju.momd` lives) regardless of which target/process is
/// hosting this code (app run vs. `LajuTests`).
private final class BundleToken {}
