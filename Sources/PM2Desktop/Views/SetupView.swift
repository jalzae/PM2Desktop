import SwiftUI

struct SetupView: View {
    @EnvironmentObject var store: PM2Store

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("PM2 Desktop")
                .font(.largeTitle.bold())
            Text("Node.js and PM2 are required to manage processes.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                requirementRow(
                    title: "Node.js",
                    installed: store.nodePath != nil,
                    path: store.nodePath
                )
                Divider()
                requirementRow(
                    title: "PM2",
                    installed: store.pm2Path != nil,
                    path: store.pm2Path
                )
            }
            .padding(18)
            .frame(maxWidth: 460)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.1))
            )

            actionButton

            if let status = store.statusText {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: 460)
            }

            if let error = store.errorText {
                banner(text: error, color: .red, dismiss: { store.errorText = nil })
            }
            if let notice = store.noticeText {
                banner(text: notice, color: .accentColor, dismiss: { store.noticeText = nil })
            }

            Button("Rescan") {
                Task { await store.checkEnvironment() }
            }
            .disabled(store.isBusy)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var actionButton: some View {
        if store.setupState == .needNode {
            Button {
                Task { await store.installNode() }
            } label: {
                Text(store.isBusy ? "Installing…" : "Install Node.js")
                    .frame(minWidth: 160)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(store.isBusy)
        } else if store.setupState == .needPM2 {
            Button {
                Task { await store.installPM2() }
            } label: {
                Text(store.isBusy ? "Installing…" : "Install PM2")
                    .frame(minWidth: 160)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(store.isBusy)
        }
    }

    private func requirementRow(title: String, installed: Bool, path: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(installed ? Color.green : Color.secondary)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                if let path {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("Not found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func banner(text: String, color: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: 460)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
