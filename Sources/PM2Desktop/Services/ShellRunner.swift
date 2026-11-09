import Foundation

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var output: String {
        (stdout + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var succeeded: Bool { exitCode == 0 }
}

enum ShellError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String)
    case timedOut(command: String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let command, let code, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "`\(command)` failed (exit code \(code))."
                : "`\(command)` failed (exit code \(code)):\n\n\(trimmed)"
        case .timedOut(let command):
            return "`\(command)` timed out."
        case .notFound(let binary):
            return "Could not find `\(binary)`."
        }
    }
}

/// GUI apps do not inherit the user's shell PATH, so we search the usual
/// install locations (including version managers) ourselves.
final class ShellRunner {
    static let shared = ShellRunner()

    let searchPaths: [String]

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths: [String] = Self.versionManagerPaths(home: home)
        paths.append(contentsOf: [
            home + "/.npm-global/bin",
            home + "/.bun/bin",
            home + "/.volta/bin",
            home + "/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ])
        searchPaths = paths
    }

    /// Newer version-manager installs first so they win over system copies.
    private static func versionManagerPaths(home: String) -> [String] {
        let fm = FileManager.default
        var result: [String] = []

        let nvmBase = home + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmBase) {
            result += versions
                .sorted { compareVersions($0, $1) }
                .map { nvmBase + "/\($0)/bin" }
        }

        let fnmBase = home + "/.fnm/node-versions"
        if let versions = try? fm.contentsOfDirectory(atPath: fnmBase) {
            result += versions
                .sorted { compareVersions($0, $1) }
                .map { fnmBase + "/\($0)/installation/bin" }
        }

        return result
    }

    private static func compareVersions(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func findBinary(_ name: String) -> String? {
        findBinaries(name).first
    }

    /// All matching executables across search paths, in search-path order.
    func findBinaries(_ name: String) -> [String] {
        var found: [String] = []
        for dir in searchPaths {
            let candidate = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                found.append(candidate)
            }
        }
        return found
    }

    /// Run a shell command with our augmented PATH. Async, with a hard timeout.
    @discardableResult
    func run(
        _ command: String,
        cwd: String? = nil,
        timeout: TimeInterval = 60
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPaths.joined(separator: ":")
        process.environment = environment

        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let timeoutFlag = TimeoutFlag()

        return try await withCheckedThrowingContinuation { continuation in
            let timer = DispatchWorkItem {
                timeoutFlag.set()
                if process.isRunning { process.terminate() }
            }
            process.terminationHandler = { proc in
                timer.cancel()
                let stdout = String(
                    data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if timeoutFlag.get() {
                    continuation.resume(throwing: ShellError.timedOut(command: command))
                } else {
                    continuation.resume(returning: ShellResult(
                        exitCode: proc.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }
            }
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            } catch {
                timer.cancel()
                continuation.resume(throwing: ShellError.commandFailed(
                    command: command,
                    exitCode: -1,
                    output: error.localizedDescription
                ))
            }
        }
    }

    /// Run and throw on non-zero exit.
    @discardableResult
    func runChecked(
        _ command: String,
        cwd: String? = nil,
        timeout: TimeInterval = 60
    ) async throws -> ShellResult {
        let result = try await run(command, cwd: cwd, timeout: timeout)
        guard result.succeeded else {
            throw ShellError.commandFailed(
                command: command,
                exitCode: result.exitCode,
                output: result.output
            )
        }
        return result
    }
}

/// Thread-safe timeout flag shared between the timer and termination handler.
private final class TimeoutFlag {
    private let lock = NSLock()
    private var value = false

    func get() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func set() {
        lock.lock(); value = true; lock.unlock()
    }
}

/// Quote a string for safe use in a shell command.
func shellEscape(_ string: String) -> String {
    guard !string.isEmpty else { return "''" }
    let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-=./:,+@%^")
    if string.rangeOfCharacter(from: safe.inverted) == nil {
        return string
    }
    return "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
