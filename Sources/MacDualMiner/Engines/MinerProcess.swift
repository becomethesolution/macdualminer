import Foundation
import Observation

/// Runs one mining engine as a child process: captures its output line by line,
/// stops it cleanly, and restarts it with back-off if it exits unexpectedly.
@MainActor
@Observable
final class MinerProcess {
    enum State: Equatable {
        case stopped
        case running
        case restarting(String)
        case failed(String)

        var label: String {
            switch self {
            case .stopped: return "Stopped"
            case .running: return "Running"
            case .restarting(let why): return "Restarting – \(why)"
            case .failed(let why): return "Failed – \(why)"
            }
        }
    }

    let name: String
    private(set) var state: State = .stopped
    private(set) var log: [String] = []
    private(set) var startedAt: Date?

    /// Called on the main actor for every complete output line.
    @ObservationIgnored var onLine: ((String) -> Void)?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var launch: (exe: URL, args: [String], env: [String: String], cwd: URL)?
    @ObservationIgnored private var partialLine = ""
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private let maxLogLines = 600

    init(name: String) { self.name = name }

    var isRunning: Bool { state == .running }

    func start(executable: URL, arguments: [String], environment: [String: String] = [:], workingDirectory: URL) {
        stop()
        launch = (executable, arguments, environment, workingDirectory)
        stopRequested = false
        consecutiveFailures = 0
        spawn()
    }

    func stop() {
        stopRequested = true
        restartTask?.cancel()
        restartTask = nil
        if let proc = process, proc.isRunning {
            let pid = proc.processIdentifier
            proc.terminate() // SIGTERM
            Task.detached {
                try? await Task.sleep(for: .seconds(5))
                if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            }
        }
        process = nil
        startedAt = nil
        state = .stopped
    }

    func clearLog() { log.removeAll() }

    private func spawn() {
        guard let launch else { return }
        guard FileManager.default.isExecutableFile(atPath: launch.exe.path) else {
            state = .failed("engine not found at \(launch.exe.path) – rebuild the app with scripts/build-app.sh")
            return
        }

        let proc = Process()
        proc.executableURL = launch.exe
        proc.arguments = launch.args
        proc.currentDirectoryURL = launch.cwd
        var env = ProcessInfo.processInfo.environment
        for (key, value) in launch.env { env[key] = value }
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        proc.standardInput = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.ingest(text) }
        }

        proc.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in self?.handleExit(of: finished, status: status) }
        }

        do {
            try proc.run()
            EngineReaper.record(pid: proc.processIdentifier)
            process = proc
            startedAt = Date()
            state = .running
            append("— \(name) started: \(launch.exe.lastPathComponent) \(redacted(launch.args).joined(separator: " "))")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func handleExit(of finished: Process, status: Int32) {
        EngineReaper.forget(pid: finished.processIdentifier)
        guard finished === process else { return } // an old process we already replaced
        process = nil
        startedAt = nil
        flushPartialLine()
        if stopRequested {
            state = .stopped
            return
        }
        consecutiveFailures += 1
        let delay = min(60, 5 * consecutiveFailures)
        append("— \(name) exited with status \(status); restarting in \(delay)s")
        state = .restarting("exit \(status), retry in \(delay)s")
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.spawnIfStillWanted()
        }
    }

    private func spawnIfStillWanted() {
        guard !stopRequested else { return }
        spawn()
        // A run that survives two minutes resets the back-off.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            if let self, self.state == .running { self.consecutiveFailures = 0 }
        }
    }

    private func ingest(_ text: String) {
        partialLine += text
        // Engines use both \n and \r (progress bars); treat either as a line break.
        var parts = partialLine.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
        partialLine = parts.isEmpty ? "" : String(parts.removeLast())
        for part in parts where !part.trimmingCharacters(in: .whitespaces).isEmpty {
            let line = stripANSI(String(part))
            append(line)
            onLine?(line)
        }
    }

    private func flushPartialLine() {
        let rest = partialLine.trimmingCharacters(in: .whitespacesAndNewlines)
        partialLine = ""
        if !rest.isEmpty {
            append(stripANSI(rest))
            onLine?(rest)
        }
    }

    private func append(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.append("[\(stamp)] \(line)")
        if log.count > maxLogLines { log.removeFirst(log.count - maxLogLines) }
    }

    /// Hide API tokens from the visible log.
    private func redacted(_ args: [String]) -> [String] {
        var out: [String] = []
        var hideNext = false
        for arg in args {
            if hideNext { out.append("••••"); hideNext = false; continue }
            out.append(arg)
            if arg == "--http-access-token" { hideNext = true }
        }
        return out
    }

    private func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }
}
