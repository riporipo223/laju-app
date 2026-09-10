import SwiftUI

@main
struct LajuApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RunTrackingView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
