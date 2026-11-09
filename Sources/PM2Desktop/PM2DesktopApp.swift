import SwiftUI

@main
struct PM2DesktopApp: App {
    @StateObject private var store = PM2Store()

    var body: some Scene {
        WindowGroup("PM2 Desktop") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 540)
        }
        .windowResizability(.contentMinSize)
    }
}
