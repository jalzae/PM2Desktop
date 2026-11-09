import SwiftUI

struct LogsSheet: View {
    @EnvironmentObject var store: PM2Store
    @Environment(\.dismiss) private var dismiss

    let process: PM2Process

    @State private var text = "Loading logs…"
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(process.statusColor)
                    .frame(width: 8, height: 8)
                Text("Logs — \(process.name)")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload logs")
                .disabled(isLoading)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 700, height: 480)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        text = await store.logs(for: process)
    }
}
