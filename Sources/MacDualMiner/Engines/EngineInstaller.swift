import Foundation
import Observation
import CryptoKit

/// Downloads UselethMiner from its author's GitHub release, checks the SHA-256 and installs the .pkg with
/// Apple's installer into /usr/local/uselethminer – the only place it runs from. macOS asks for an admin
/// password once (install and remove). The package has no install scripts; it only copies files.
@MainActor
@Observable
final class UselethInstaller {
    static let version = "0.23"
    static let url = URL(string: "https://github.com/Chainfire/UselethMiner/releases/download/v0.23/uselethminer-0.23-macos-arm64.pkg")!
    nonisolated static let sha256 = "00f50fd952ff88a13ff7abf57d2f92e4bf1d25d3031ce906f124eaa583bd3be3"
    nonisolated static let packageID = "eu.chainfire.uselethminer.macos.arm64"

    private(set) var status: String?
    private(set) var isWorking = false

    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: AppPaths.uselethExecutable.path) }

    init() {
        // The old in-app copy can't run (see AppPaths.uselethDirectory); free its ~65 MB.
        let legacy = AppPaths.legacyUselethDirectory
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.removeItem(at: legacy)
            if !isInstalled { status = "UselethMiner needs to be installed again – the earlier copy couldn't run." }
        }
    }

    func install() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let fm = FileManager.default
        let work = AppPaths.cacheDirectory.appendingPathComponent("useleth-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            status = "Downloading UselethMiner \(Self.version) (21.6 MB) from github.com/Chainfire…"
            let (downloaded, response) = try await URLSession.shared.download(from: Self.url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError("download failed") }
            let pkg = work.appendingPathComponent("uselethminer-\(Self.version).pkg")
            try fm.moveItem(at: downloaded, to: pkg)

            status = "Checking the download, then installing – macOS will ask for your password…"
            try await Task.detached(priority: .userInitiated) {
                try Self.verify(pkg: pkg)
                try Self.runAsAdmin("/usr/sbin/installer -pkg \(Self.shellQuote(pkg.path)) -target /",
                                    prompt: "MacDualMiner wants to install UselethMiner in /usr/local/uselethminer.")
            }.value
            guard isInstalled else { throw InstallError("the installer finished but uselethminer is missing") }
            status = "UselethMiner \(Self.version) installed"
        } catch {
            status = "Couldn't install UselethMiner: \(error.localizedDescription)"
        }
    }

    func uninstall() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try Self.runAsAdmin("/bin/rm -rf /usr/local/uselethminer; /usr/sbin/pkgutil --forget \(Self.packageID) >/dev/null 2>&1; true",
                                    prompt: "MacDualMiner wants to remove UselethMiner from /usr/local/uselethminer.")
            }.value
            status = isInstalled ? "Couldn't remove UselethMiner" : "UselethMiner removed (its DAG files stay in ~/.uselethminer)"
        } catch {
            status = "Couldn't remove UselethMiner: \(error.localizedDescription)"
        }
    }

    nonisolated static func verify(pkg: URL) throws {
        let digest = SHA256.hash(data: try Data(contentsOf: pkg)).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw InstallError("checksum mismatch (got \(digest.prefix(12))…) – not installed") }
    }

    nonisolated static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Runs a shell command as root via the standard macOS password prompt.
    nonisolated private static func runAsAdmin(_ command: String, prompt: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "on run argv",
                       "-e", "do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges",
                       "-e", "end run", command, prompt]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if msg.contains("-128") { throw InstallError("cancelled") }
            throw InstallError(msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "admin command failed" : msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

struct InstallError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
