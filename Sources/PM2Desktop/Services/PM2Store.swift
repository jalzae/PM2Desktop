import SwiftUI

/// Configuration for a new PM2 process submitted from the add sheet.
struct NewProcessConfig {
    var name: String
    var scriptPath: String
    var cwd: String
    var args: String
    var interpreter: String // "" or "auto" = let PM2 decide
    var buildCommand: String
    var autoRestart: Bool
}

@MainActor
final class PM2Store: ObservableObject {
    enum SetupState: Equatable {
        case checking
        case needNode
        case needPM2
        case ready
    }

    enum ProcessAction: String, CaseIterable {
        case start, stop, restart, delete

        var progressLabel: String {
            switch self {
            case .start: return "Starting"
            case .stop: return "Stopping"
            case .restart: return "Restarting"
            case .delete: return "Deleting"
            }
        }
    }

    @Published private(set) var setupState: SetupState = .checking
    @Published private(set) var processes: [PM2Process] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isBusy = false
    @Published private(set) var nodePath: String?
    @Published private(set) var pm2Path: String?
    @Published private(set) var pm2InstalledToUserPrefix = false

    @Published var statusText: String?
    @Published var errorText: String?
    @Published var noticeText: String?
    @Published var filter = ""

    var filteredProcesses: [PM2Process] {
        guard !filter.isEmpty else { return processes }
        return processes.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var onlineCount: Int {
        processes.filter { $0.isRunning }.count
    }

    // MARK: - Detection

    func checkEnvironment() async {
        nodePath = ShellRunner.shared.findBinary("node")
        guard nodePath != nil else {
            setupState = .needNode
            return
        }

        pm2Path = await pickBestPM2()
        guard pm2Path != nil else {
            setupState = .needPM2
            return
        }

        setupState = .ready
        await refresh()
    }

    /// Several PM2 installs can coexist (nvm versions, bun, npm-global).
    /// The PM2 daemon has one version; a mismatched CLI prints warnings into
    /// stdout and pollutes `pm2 jlist`. Pick the newest candidate by --version.
    private func pickBestPM2() async -> String? {
        let candidates = ShellRunner.shared.findBinaries("pm2")
        guard !candidates.isEmpty else { return nil }

        var best: (path: String, version: (Int, Int, Int))?
        for candidate in candidates {
            guard let result = try? await ShellRunner.shared.run(
                "\(shellEscape(candidate)) --version",
                timeout: 15
            ), result.succeeded else { continue }

            let parts = result.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ".")
                .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
            guard parts.contains(where: { $0 > 0 }) else { continue }
            let version = (parts.count > 0 ? parts[0] : 0,
                           parts.count > 1 ? parts[1] : 0,
                           parts.count > 2 ? parts[2] : 0)

            if best == nil || version > best!.version {
                best = (candidate, version)
            }
        }
        return best?.path ?? candidates.first
    }

    // MARK: - Installation

    func installNode() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorText = nil
        noticeText = nil

        do {
            if ShellRunner.shared.findBinary("brew") != nil {
                statusText = "Installing Node.js via Homebrew — this can take a few minutes…"
                try await ShellRunner.shared.runChecked("brew install node", timeout: 1800)
            } else {
                statusText = "Homebrew not found — downloading the official Node.js installer…"
                let pkgPath = try await downloadNodeInstaller()
                statusText = "Installing Node.js (administrator permission required)…"
                let shellCommand = "installer -pkg \(shellEscape(pkgPath)) -target /"
                let appleScript = "do shell script \(appleScriptQuoted(shellCommand)) with administrator privileges"
                try await ShellRunner.shared.runChecked(
                    "osascript -e \(shellEscape(appleScript))",
                    timeout: 1800
                )
                try? FileManager.default.removeItem(atPath: pkgPath)
            }

            statusText = "Verifying installation…"
            await checkEnvironment()
            if setupState == .needNode {
                throw ShellError.commandFailed(
                    command: "install node",
                    exitCode: 1,
                    output: "Node.js still not found after installation. Try restarting the app."
                )
            }
            noticeText = "Node.js installed successfully."
        } catch {
            errorText = error.localizedDescription
        }
        statusText = nil
    }

    func installPM2() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorText = nil
        noticeText = nil

        do {
            guard ShellRunner.shared.findBinary("node") != nil else {
                setupState = .needNode
                return
            }
            guard let npm = ShellRunner.shared.findBinary("npm") else {
                throw ShellError.notFound("npm")
            }

            statusText = "Installing PM2 via npm — this can take a minute…"
            let result = try await ShellRunner.shared.run("npm install -g pm2", timeout: 900)

            if !result.succeeded {
                let output = result.output.lowercased()
                if output.contains("eacces") || output.contains("permission denied") {
                    statusText = "Global install needs permissions — installing to ~/.npm-global instead…"
                    let fallback = """
                    mkdir -p "$HOME/.npm-global" && \
                    \(shellEscape(npm)) install -g pm2 --prefix "$HOME/.npm-global"
                    """
                    try await ShellRunner.shared.runChecked(fallback, timeout: 900)
                    pm2InstalledToUserPrefix = true
                } else {
                    throw ShellError.commandFailed(
                        command: "npm install -g pm2",
                        exitCode: result.exitCode,
                        output: result.output
                    )
                }
            }

            statusText = "Verifying installation…"
            await checkEnvironment()
            if setupState == .needPM2 {
                throw ShellError.commandFailed(
                    command: "pm2 check",
                    exitCode: 1,
                    output: "PM2 still not found after installation. Try restarting the app."
                )
            }
            noticeText = pm2InstalledToUserPrefix
                ? "PM2 installed to ~/.npm-global/bin — add that directory to your shell PATH to use it in Terminal."
                : "PM2 installed successfully."
        } catch {
            errorText = error.localizedDescription
        }
        statusText = nil
    }

    private func downloadNodeInstaller() async throws -> String {
        struct DistIndex: Decodable {
            let version: String
            let lts: StringOrBool?

            enum StringOrBool: Decodable {
                case string(String)
                case bool(Bool)

                var isLTS: Bool {
                    if case .string = self { return true }
                    return false
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let bool = try? container.decode(Bool.self) {
                        self = .bool(bool)
                    } else {
                        self = .string(try container.decode(String.self))
                    }
                }
            }
        }

        statusText = "Fetching Node.js release list…"
        let indexURL = URL(string: "https://nodejs.org/dist/index.json")!
        let (data, _) = try await URLSession.shared.data(from: indexURL)
        let releases = try JSONDecoder().decode([DistIndex].self, from: data)
        guard let latest = releases.first(where: { $0.lts?.isLTS ?? false }) else {
            throw ShellError.commandFailed(
                command: "fetch releases",
                exitCode: 0,
                output: "No LTS release found on nodejs.org."
            )
        }

        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x64"
        #endif

        let file = "node-\(latest.version)-darwin-\(arch).pkg"
        guard let downloadURL = URL(string: "https://nodejs.org/dist/\(latest.version)/\(file)") else {
            throw ShellError.commandFailed(
                command: "build download URL",
                exitCode: 0,
                output: "Invalid URL for \(file)."
            )
        }

        statusText = "Downloading \(file)…"
        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(file)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination.path
    }

    private func appleScriptQuoted(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: - Listing

    func refresh() async {
        guard setupState == .ready else { return }
        do {
            let result = try await ShellRunner.shared.run("pm2 jlist", timeout: 30)
            let json = jsonPayload(from: result.stdout)
            let entries = try JSONDecoder().decode([RawEntry].self, from: Data(json.utf8))
            processes = entries.map(PM2Process.init(raw:))
            lastRefresh = Date()
            errorText = nil
        } catch {
            errorText = "Failed to read the PM2 list: \(error.localizedDescription)"
        }
    }

    func refreshIfIdle() async {
        guard !isBusy else { return }
        await refresh()
    }

    // MARK: - Actions

    func perform(_ action: ProcessAction, on process: PM2Process) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorText = nil

        let target = shellEscape(process.name)
        let command: String
        switch action {
        case .start: command = "pm2 start \(target)"
        case .stop: command = "pm2 stop \(target)"
        case .restart: command = "pm2 restart \(target)"
        case .delete: command = "pm2 delete \(target)"
        }

        statusText = "\(action.progressLabel) \(process.name)…"
        do {
            try await ShellRunner.shared.runChecked(command, timeout: 60)
            await refresh()
        } catch {
            errorText = error.localizedDescription
        }
        statusText = nil
    }

    // MARK: - Create

    func addProcess(_ config: NewProcessConfig) async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorText = nil

        let cwd = config.cwd.isEmpty ? FileManager.default.currentDirectoryPath : config.cwd

        if !config.buildCommand.isEmpty {
            statusText = "Running build for \(config.name)…"
            let build = "cd \(shellEscape(cwd)) && \(config.buildCommand)"
            let result = try await ShellRunner.shared.run(build, cwd: cwd, timeout: 1800)
            guard result.succeeded else {
                throw ShellError.commandFailed(
                    command: config.buildCommand,
                    exitCode: result.exitCode,
                    output: result.output
                )
            }
        }

        var parts = [
            "pm2", "start",
            shellEscape(config.scriptPath),
            "--name", shellEscape(config.name),
        ]
        let interpreter = config.interpreter.trimmingCharacters(in: .whitespaces).lowercased()
        if !interpreter.isEmpty && interpreter != "auto" {
            parts += ["--interpreter", shellEscape(interpreter)]
        }
        if !config.autoRestart {
            parts.append("--no-autorestart")
        }
        let argList = config.args
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map(shellEscape)
        if !argList.isEmpty {
            parts.append("--")
            parts += argList
        }

        statusText = "Starting \(config.name)…"
        try await ShellRunner.shared.runChecked(parts.joined(separator: " "), timeout: 120)
        await refresh()
    }

    /// PM2 CLIs can print version banners before the JSON on stdout.
    /// Keep only the outermost JSON payload.
    private func jsonPayload(from output: String) -> String {
        if let start = output.firstIndex(of: "["),
           let end = output.lastIndex(of: "]"),
           start < end {
            return String(output[start...end])
        }
        if let start = output.firstIndex(of: "{"),
           let end = output.lastIndex(of: "}"),
           start < end {
            return String(output[start...end])
        }
        return output
    }

    // MARK: - Logs

    func logs(for process: PM2Process, maxLines: Int = 400) async -> String {
        var sections: [String] = []
        for (label, path) in [("stdout", process.outLog), ("stderr", process.errLog)] {
            guard let path, FileManager.default.fileExists(atPath: path) else { continue }
            if let result = try? await ShellRunner.shared.run(
                "tail -n \(maxLines) \(shellEscape(path))",
                timeout: 15
            ), !result.stdout.isEmpty {
                let body = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                sections.append("── \(label) · \(path) ──\n\(body)")
            }
        }
        return sections.isEmpty
            ? "No log output yet for \(process.name)."
            : sections.joined(separator: "\n\n")
    }
}
