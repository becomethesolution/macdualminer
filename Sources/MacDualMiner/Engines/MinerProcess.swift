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
    @ObservationIgnored private var launch: (exe: URL, args: [String], env: [String: String], cwd: URL, pty: Bool)?
    @ObservationIgnored private var ptySource: DispatchSourceRead?
    @ObservationIgnored private var partialLine = ""
    @ObservationIgnored private var stopRequested = false
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private let maxLogLines = 600

    /// Share of time the engine is allowed to run (0.1…1). Below 1 the process is paused and resumed
    /// (SIGSTOP/SIGCONT) in short bursts – a universal power limiter for engines with no intensity setting.
    /// (No `didSet` that re-assigns the property: under @Observable that recursed forever – the 0.2.0 launch crash.)
    var dutyCycle: Double {
        get { storedDutyCycle }
        set {
            let clamped = min(1, max(0.1, newValue))
            guard clamped != storedDutyCycle else { return }
            storedDutyCycle = clamped
            updateThrottle()
        }
    }

    @ObservationIgnored private var storedDutyCycle: Double = 1

    @ObservationIgnored private var throttleTask: Task<Void, Never>?

    init(name: String) { self.name = name }

    var isRunning: Bool { state == .running }

    private func updateThrottle() {
        throttleTask?.cancel()
        throttleTask = nil
        if let pid = process?.processIdentifier { kill(pid, SIGCONT) }
        guard dutyCycle < 0.999, let proc = process, proc.isRunning else { return }
        let pid = proc.processIdentifier
        let on = dutyCycle, period = 1.0
        throttleTask = Task.detached(priority: .high) {
            while !Task.isCancelled {
                kill(pid, SIGCONT)
                try? await Task.sleep(for: .milliseconds(Int(period * on * 1000)))
                guard !Task.isCancelled else { break }
                kill(pid, SIGSTOP)
                try? await Task.sleep(for: .milliseconds(Int(period * (1 - on) * 1000)))
            }
            kill(pid, SIGCONT)
        }
    }

    /// `pseudoTerminal`: give the engine a terminal instead of a pipe. Engines that buffer their output when
    /// it isn't a terminal (UselethMiner, a compiled Python program) then print each line as it happens.
    func start(executable: URL, arguments: [String], environment: [String: String] = [:], workingDirectory: URL,
               pseudoTerminal: Bool = false) {
        stop()
        launch = (executable, arguments, environment, workingDirectory, pseudoTerminal)
        stopRequested = false
        consecutiveFailures = 0
        spawn()
    }

    func stop() {
        stopRequested = true
        restartTask?.cancel()
        restartTask = nil
        throttleTask?.cancel()
        throttleTask = nil
        if let proc = process, proc.isRunning {
            let pid = proc.processIdentifier
            kill(pid, SIGCONT)  // a paused process can't act on SIGTERM
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

        proc.standardInput = FileHandle.nullDevice
        var ptyMaster: Int32 = -1
        var ptySlave: FileHandle?
        if launch.pty, let (master, slave) = Self.openPseudoTerminal() {
            ptyMaster = master
            let handle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
            proc.standardOutput = handle
            proc.standardError = handle
            ptySlave = handle
        } else {
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                let text = String(decoding: data, as: UTF8.self)
                Task { @MainActor [weak self] in self?.ingest(text) }
            }
        }

        proc.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in self?.handleExit(of: finished, status: status) }
        }

        do {
            try proc.run()
            // The child has its own copy of the terminal; closing ours lets reads end when the engine exits.
            try? ptySlave?.close()
            if ptyMaster >= 0 { readPseudoTerminal(ptyMaster) }
            EngineReaper.record(pid: proc.processIdentifier)
            process = proc
            updateThrottle()
            startedAt = Date()
            state = .running
            append("— \(name) started: \(launch.exe.lastPathComponent) \(redacted(launch.args).joined(separator: " "))")
        } catch {
            try? ptySlave?.close()
            if ptyMaster >= 0 { close(ptyMaster) }
            state = .failed(error.localizedDescription)
        }
    }

    /// Opens a pseudo-terminal with output post-processing and echo off (no "\r\n" rewriting).
    nonisolated private static func openPseudoTerminal() -> (master: Int32, slave: Int32)? {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return nil }
        var attrs = termios()
        if tcgetattr(slave, &attrs) == 0 {
            attrs.c_oflag &= ~tcflag_t(OPOST)
            attrs.c_lflag &= ~tcflag_t(ECHO)
            _ = tcsetattr(slave, TCSANOW, &attrs)
        }
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        return (master, slave)
    }

    /// Reads the terminal with read(2): once the engine exits a terminal read fails with EIO, which
    /// FileHandle would raise as an exception instead of returning end-of-file.
    private func readPseudoTerminal(_ fd: Int32) {
        ptySource?.cancel()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 16_384)
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                let text = String(decoding: buffer[0..<count], as: UTF8.self)
                Task { @MainActor [weak self] in self?.ingest(text) }
            } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                source.cancel()   // Dispatch releases this handler once cancelled
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        ptySource = source
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
