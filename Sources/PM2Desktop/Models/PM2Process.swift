import SwiftUI

/// Subset of the JSON emitted by `pm2 jlist`.
struct RawEntry: Decodable {
    let name: String
    let pid: Int?
    let pm_id: Int?
    let pm2_env: RawEnv?
    let monit: RawMonit?

    struct RawEnv: Decodable {
        let status: String?
        let pm_uptime: Double?
        let restart_time: Int?
        let pm_out_log_path: String?
        let pm_err_log_path: String?
        let pm_cwd: String?
        let pm_exec_path: String?
        let exec_interpreter: String?
    }

    struct RawMonit: Decodable {
        let memory: Double?
        let cpu: Double?
    }
}

struct PM2Process: Identifiable, Equatable {
    let id: Int
    let name: String
    let pid: Int?
    let status: String
    let cpu: Double
    let memory: Int64
    let uptimeStart: Date?
    let restarts: Int
    let scriptPath: String?
    let cwd: String?
    let outLog: String?
    let errLog: String?

    init(raw: RawEntry) {
        id = raw.pm_id ?? raw.pid ?? 0
        name = raw.name
        pid = raw.pid
        status = raw.pm2_env?.status ?? "unknown"
        cpu = raw.monit?.cpu ?? 0
        memory = Int64(raw.monit?.memory ?? 0)
        if let up = raw.pm2_env?.pm_uptime, up > 0 {
            uptimeStart = Date(timeIntervalSince1970: up / 1000)
        } else {
            uptimeStart = nil
        }
        restarts = raw.pm2_env?.restart_time ?? 0
        scriptPath = raw.pm2_env?.pm_exec_path
        cwd = raw.pm2_env?.pm_cwd
        outLog = raw.pm2_env?.pm_out_log_path
        errLog = raw.pm2_env?.pm_err_log_path
    }

    var isRunning: Bool { status == "online" }

    var statusLabel: String {
        switch status {
        case "online": return "Running"
        case "stopped": return "Stopped"
        case "launching": return "Launching"
        case "errored": return "Errored"
        default: return status.capitalized
        }
    }

    var statusColor: Color {
        switch status {
        case "online": return .green
        case "launching": return .orange
        case "errored": return .red
        default: return .gray
        }
    }
}
