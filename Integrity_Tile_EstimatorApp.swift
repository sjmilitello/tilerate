import SwiftUI
import SwiftData

@main
struct IntegrityTileEstimatorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Attach SwiftData container here:
        .modelContainer(for: [AdminSettingsEntity.self])
    }
}
