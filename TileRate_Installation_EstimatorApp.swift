
import SwiftUI

@main
struct TileRateApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            Group {
                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                } else {
                    RootView()
                }
            }
            .applyGlobalTapToDismiss()
        }
    }
}
