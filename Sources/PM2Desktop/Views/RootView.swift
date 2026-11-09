import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: PM2Store

    var body: some View {
        switch store.setupState {
        case .checking:
            VStack(spacing: 12) {
                ProgressView()
                Text("Detecting Node.js and PM2…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await store.checkEnvironment() }

        case .needNode, .needPM2:
            SetupView()
                .task { await store.checkEnvironment() }

        case .ready:
            ProcessListView()
        }
    }
}
