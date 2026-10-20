import Foundation
import Observation
import AppKit

/// Checks GitHub for a newer MacDualMiner release and can install it in place.
@MainActor
@Observable
final class UpdateService {
    static let repository = "becomethesolution/macdualminer"

    enum State: Equatable {
        case idle, checking, upToDate, available(ReleaseInfo), downloading(String), failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    @ObservationIgnored private var task: Task<Void, Never>?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var available: ReleaseInfo? {
        if case .available(let info) = state { return info }
        return nil
    }

    /// Checks shortly after launch, then every 6 hours, while `enabled()` is true.
    func start(enabled: @escaping @MainActor () -> Bool) {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            while !Task.isCancelled {
                if enabled() { await self?.check() }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    func check() async {
        if case .downloading = state { return }
        state = .checking
        defer { lastChecked = Date() }
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else { return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacDualMiner/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              case let (data, response) = result,
              (response as? HTTPURLResponse)?.statusCode == 200,
              let info = ReleaseInfo.parse(data) else {
            state = .failed("Couldn't reach GitHub to check for updates")
            return
        }
        if let latest = AppVersion(info.version), let current = AppVersion(currentVersion), current < latest {
            state = .available(info)
        } else {
            state = .upToDate
        }
    }

    func openReleasePage() {
        if let info = available { NSWorkspace.shared.open(info.pageURL) }
        else if let url = URL(string: "https://github.com/\(Self.repository)/releases/latest") { NSWorkspace.shared.open(url) }
    }

    /// Downloads the release zip, checks it's a MacDualMiner build of the expected version with a valid
    /// signature, swaps it in for the running app and relaunches. Falls back to the release page if the
    /// app's folder isn't writable (e.g. run from a disk image).
    func installUpdate(beforeRelaunch: @escaping @MainActor () -> Void) async {
        guard let info = available, let zipURL = info.zipURL else { openReleasePage(); return }
        let fm = FileManager.default
        // A downloaded app that still carries the quarantine flag is run by macOS from a read-only
        // "App Translocation" copy; update the real app where the user put it instead.
        let current = Translocation.originalURL(for: Bundle.main.bundleURL)
        guard fm.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            state = .failed("Can't replace the app in \(current.deletingLastPathComponent().path) – opening the release page instead")
            openReleasePage()
            return
        }
        let work = AppPaths.cacheDirectory.appendingPathComponent("update-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            state = .downloading("Downloading MacDualMiner \(info.version)…")
            let (file, response) = try await URLSession.shared.download(from: zipURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError("download failed") }
            let zip = work.appendingPathComponent("update.zip")
            try fm.moveItem(at: file, to: zip)

            state = .downloading("Verifying…")
            let newApp = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
                let app = work.appendingPathComponent("MacDualMiner.app")
                guard let bundle = Bundle(url: app),
                      bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                      (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) == info.version
                else { throw InstallError("the download isn't MacDualMiner \(info.version)") }
                try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
                // Verified above, so drop any quarantine flag: otherwise macOS translocates it again.
                try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
                return app
            }.value

            state = .downloading("Installing and restarting…")
            beforeRelaunch()                       // stop the engines first
            _ = try fm.replaceItemAt(current, withItemAt: newApp, backupItemName: nil, options: [])
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", current.path]
            try relaunch.run()
            NSApp.terminate(nil)
        } catch {
            try? fm.removeItem(at: work)
            state = .failed("Update failed: \(error.localizedDescription)")
        }
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw InstallError("\(URL(fileURLWithPath: tool).lastPathComponent) failed (\(p.terminationStatus))")
        }
    }
}

/// Finds where a translocated app really lives, using Security.framework's SecTranslocate calls
/// (looked up at run time; they're public C functions without a Swift header).
enum Translocation {
    private typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutableRawPointer?) -> Bool
    private typealias OriginalPath = @convention(c) (CFURL, UnsafeMutableRawPointer?) -> Unmanaged<CFURL>?

    static func isTranslocated(_ url: URL) -> Bool { url.path.contains("/AppTranslocation/") }

    static func originalURL(for url: URL) -> URL {
        guard isTranslocated(url),
              let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else { return url }
        defer { dlclose(handle) }
        guard let isSym = dlsym(handle, "SecTranslocateIsTranslocatedURL"),
              let origSym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return url }
        var translocated = false
        guard unsafeBitCast(isSym, to: IsTranslocated.self)(url as CFURL, &translocated, nil), translocated,
              let original = unsafeBitCast(origSym, to: OriginalPath.self)(url as CFURL, nil)?.takeRetainedValue()
        else { return url }
        return original as URL
    }
}
