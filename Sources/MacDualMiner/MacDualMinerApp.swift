import SwiftUI
import AppKit

@main
struct MacDualMinerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("MacDualMiner", id: "dashboard") {
            MainWindow()
                .environment(appDelegate.coordinator)
                .environment(appDelegate.ui)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 900, height: 680)

        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.coordinator)
                .environment(appDelegate.ui)
        } label: {
            MenuBarLabel(coordinator: appDelegate.coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.coordinator)
                .environment(appDelegate.ui)
                .frame(width: 640, height: 580)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let ui = UIState()
    lazy var coordinator: MiningCoordinator = {
        EngineReaper.killLeftoversFromLastSession()
        return MiningCoordinator(store: SettingsStore())
    }()

    /// Keep mining from the menu bar when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
        EngineReaper.killLeftoversFromLastSession()
    }
}

struct MenuBarLabel: View {
    let coordinator: MiningCoordinator

    var body: some View {
        if coordinator.isMining {
            Label(Format.usd(coordinator.earnings.net(.day)) + "/day", systemImage: "hammer.fill")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "hammer")
        }
    }
}

/// Engines run as child processes; if the app crashes they'd keep mining. We record their PIDs
/// and clean up anything left over on the next launch (and on quit).
enum EngineReaper {
    private static var file: URL { AppPaths.supportDirectory.appendingPathComponent("engine-pids.txt") }
    private static let engineNames: Set<String> = ["xmrig", "kawpow-metal"]

    static func record(pid: Int32) {
        var pids = load()
        pids.insert(pid)
        save(pids)
    }

    static func forget(pid: Int32) {
        var pids = load()
        pids.remove(pid)
        save(pids)
    }

    static func killLeftoversFromLastSession() {
        for pid in load() where engineNames.contains(processName(pid) ?? "") {
            kill(pid, SIGKILL)
        }
        save([])
    }

    private static func processName(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func load() -> Set<Int32> {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline).compactMap { Int32($0) })
    }

    private static func save(_ pids: Set<Int32>) {
        let text = pids.map(String.init).joined(separator: "\n")
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }
}
