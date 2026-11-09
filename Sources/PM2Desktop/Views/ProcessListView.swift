import SwiftUI

struct ProcessListView: View {
    @EnvironmentObject var store: PM2Store

    @State private var selectedIDs: Set<Int> = []
    @State private var showAddSheet = false
    @State private var logsTarget: PM2Process?
    @State private var deleteTarget: PM2Process?

    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var selected: PM2Process? {
        store.processes.first { selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.processes.isEmpty {
                emptyState
            } else {
                table
            }
            Divider()
            statusBar
        }
        .navigationTitle("PM2 Desktop")
        .toolbar { toolbar }
        .searchable(text: $store.filter, prompt: "Filter by name")
        .onReceive(timer) { _ in
            Task { await store.refreshIfIdle() }
        }
        .sheet(isPresented: $showAddSheet) {
            AddProcessSheet()
        }
        .sheet(item: $logsTarget) { process in
            LogsSheet(process: process)
        }
        .confirmationDialog(
            "Delete process “\(deleteTarget?.name ?? "")”?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { target in
            Button("Delete", role: .destructive) {
                Task { await store.perform(.delete, on: target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("“\(target.name)” will be removed from the PM2 list. Files on disk are not touched.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh list")
            .disabled(store.isBusy)

            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Add a new process")
            .disabled(store.isBusy)

            Divider()

            Button {
                if let selected { Task { await store.perform(.start, on: selected) } }
            } label: {
                Image(systemName: "play.fill")
            }
            .help("Start")
            .disabled(canStart == false)

            Button {
                if let selected { Task { await store.perform(.stop, on: selected) } }
            } label: {
                Image(systemName: "stop.fill")
            }
            .help("Stop")
            .disabled(canStop == false)

            Button {
                if let selected { Task { await store.perform(.restart, on: selected) } }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .help("Restart")
            .disabled(canRestart == false)

            Button {
                logsTarget = selected
            } label: {
                Image(systemName: "doc.text")
            }
            .help("View logs")
            .disabled(selected == nil || store.isBusy)

            Divider()

            Button {
                deleteTarget = selected
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .help("Delete from PM2")
            .disabled(selected == nil || store.isBusy)
        }
    }

    private var canStart: Bool {
        guard let selected else { return false }
        return !selected.isRunning && !store.isBusy
    }
    private var canStop: Bool {
        guard let selected else { return false }
        return selected.isRunning && !store.isBusy
    }
    private var canRestart: Bool {
        guard let selected else { return false }
        return selected.isRunning && !store.isBusy
    }

    // MARK: - Table

    private var table: some View {
        Table(store.filteredProcesses, selection: $selectedIDs) {
            TableColumn("") { process in
                Circle()
                    .fill(process.statusColor)
                    .frame(width: 8, height: 8)
            }
            .width(24)

            TableColumn("Name") { process in
                VStack(alignment: .leading, spacing: 1) {
                    Text(process.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(process.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 1)
            }

            TableColumn("PID") { process in
                Text(process.pid.map(String.init) ?? "—")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(60)

            TableColumn("CPU") { process in
                Text(Fmt.cpu(process.cpu))
                    .foregroundColor(process.cpu > 80 ? .orange : .primary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(55)

            TableColumn("Memory") { process in
                Text(Fmt.bytes(process.memory))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)

            TableColumn("Uptime") { process in
                Text(process.isRunning ? Fmt.uptime(since: process.uptimeStart) : "—")
                    .foregroundColor(process.isRunning ? .primary : .secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(110)

            TableColumn("Restarts") { process in
                Text("\(process.restarts)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(70)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            contextMenuItems(for: ids)
        } primaryAction: { ids in
            if let id = ids.first,
               let process = store.processes.first(where: { $0.id == id }) {
                logsTarget = process
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for ids: Set<Int>) -> some View {
        if let process = store.processes.first(where: { ids.contains($0.id) }) {
            if process.isRunning {
                Button("Stop") { Task { await store.perform(.stop, on: process) } }
                Button("Restart") { Task { await store.perform(.restart, on: process) } }
            } else {
                Button("Start") { Task { await store.perform(.start, on: process) } }
            }
            Button("Logs…") { logsTarget = process }
            Divider()
            Button("Delete…", role: .destructive) { deleteTarget = process }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(store.filter.isEmpty ? "No PM2 processes" : "No processes match “\(store.filter)”")
                .foregroundStyle(.secondary)
            if store.filter.isEmpty {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add a Process", systemImage: "plus")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text("\(store.onlineCount) running · \(store.processes.count) total")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.pm2InstalledToUserPrefix {
                Text("PM2 lives in ~/.npm-global/bin")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            if store.isBusy {
                ProgressView().controlSize(.small)
            }
            if let status = store.statusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = store.errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(error)
            }
            Text("Updated \(Fmt.time(store.lastRefresh))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Row (rendered by Table)
