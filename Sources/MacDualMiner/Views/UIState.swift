import Foundation
import Observation
import ServiceManagement

enum MainTab: Hashable { case dashboard, profit, earnings, logs }

/// View-local UI state (selected tab, filters, …) kept in one @Observable object instead of SwiftUI's `@State`.
/// With the macOS 27 SDK `@State` is a compiler macro whose plugin ships only with full Xcode, so using it
/// broke builds made with just the Command Line Tools. @Observable's macro ships with both.
@MainActor
@Observable
final class UIState {
    var mainTab: MainTab = .dashboard
    var logsEngine: EngineKind = .xmrig
    var showIneligibleCoins = true
    var profitSelection: String?
    var loginError: String?
    var launchAtLogin = SMAppService.mainApp.status == .enabled
}
