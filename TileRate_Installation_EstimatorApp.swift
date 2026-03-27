
import SwiftUI

@main
struct TileRateApp: App {
    @StateObject private var appState = AppState()
    @State private var showSplash = true
    @StateObject private var auth = AdminAuthManager()
    // Sheet binding uses AppState to decide when to present reset UI
    private var showingResetBinding: Binding<Bool> {
        Binding(
            get: { appState.pendingResetToken != nil },
            set: { isShown in if !isShown { appState.pendingResetToken = nil } }
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                    .environmentObject(appState)
                    .environmentObject(auth)
                } else {
                    RootView()
                        .environmentObject(appState)
                        .environmentObject(auth)
                }
            }
            .applyGlobalTapToDismiss()
            // Handles custom scheme deep links, e.g. myapp://reset?token=...
            .onOpenURL { url in
                appState.handleDeepLink(url)
            }
            // Handles Universal Links, e.g. https://tilerate.com/reset?token=...
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL {
                    appState.handleDeepLink(url)
                }
            }
            // Present reset sheet ABOVE whatever screen is showing
            .sheet(isPresented: showingResetBinding) {
                ResetPasswordSheet(
                    token: appState.pendingResetToken ?? "",
                    onDone: { appState.pendingResetToken = nil }
                )
                .environmentObject(auth)
                .applyGlobalTapToDismiss()             }
        }
    }
}
