import Foundation
import Observation
import CryptoKit

/// Downloads UselethMiner from its author's GitHub release, checks the SHA-256 and unpacks the .pkg payload
/// into Application Support (nothing is installed system-wide, no admin password needed).
@MainActor
@Observable
final class UselethInstaller {
    static let version = "0.23"
    static let url = URL(string: "https://github.com/Chainfire/UselethMiner/releases/download/v0.23/uselethminer-0.23-macos-arm64.pkg")!
    nonisolated static let sha256 = "00f50fd952ff88a13ff7abf57d2f92e4bf1d25d3031ce906f124eaa583bd3be3"

    private(set) var status: String?
    private(set) var isWorking = false

    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: AppPaths.uselethExecutable.path) }

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
            let pkg = work.appendingPathComponent("useleth.pkg")
            try fm.moveItem(at: downloaded, to: pkg)

            status = "Verifying checksum and unpacking…"
            try await Task.detached(priority: .userInitiated) {
                try Self.verifyAndUnpack(pkg: pkg, work: work)
            }.value
            guard isInstalled else { throw InstallError("uselethminer binary missing from the package") }
            status = "UselethMiner \(Self.version) installed"
        } catch {
            status = "Couldn't install UselethMiner: \(error.localizedDescription)"
        }
    }

    func uninstall() {
        try? FileManager.default.removeItem(at: AppPaths.uselethDirectory)
        status = "UselethMiner removed"
    }

    nonisolated static func verifyAndUnpack(pkg: URL, work: URL) throws {
        let fm = FileManager.default
        let digest = SHA256.hash(data: try Data(contentsOf: pkg)).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw InstallError("checksum mismatch (got \(digest.prefix(12))…) – not installed") }
        let expanded = work.appendingPathComponent("expanded")
        try run("/usr/sbin/pkgutil", ["--expand-full", pkg.path, expanded.path])
        let payload = try findPayload(in: expanded)
        let dest = AppPaths.uselethDirectory
        try? fm.removeItem(at: dest)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: payload, to: dest)
    }

    /// The payload folder is the one that contains the `uselethminer` executable.
    nonisolated private static func findPayload(in root: URL) throws -> URL {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { throw InstallError("empty package") }
        for case let url as URL in walker where url.lastPathComponent == "uselethminer" && fm.isExecutableFile(atPath: url.path) {
            return url.deletingLastPathComponent()
        }
        throw InstallError("uselethminer not found in the package")
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw InstallError("\(URL(fileURLWithPath: tool).lastPathComponent) exited with \(p.terminationStatus)") }
    }
}

struct InstallError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
