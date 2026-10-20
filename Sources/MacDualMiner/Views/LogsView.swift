import SwiftUI
import AppKit

struct LogsView: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UIState.self) private var uiState

    private var process: MinerProcess { coordinator.engine(uiState.logsEngine).process }

    var body: some View {
        @Bindable var ui = uiState
        VStack(spacing: 8) {
            HStack {
                Picker("Engine", selection: $ui.logsEngine) {
                    ForEach(EngineKind.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(process.log.joined(separator: "\n"), forType: .string)
                }
                Button("Clear") { process.clearLog() }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(process.log.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: process.log.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
        .padding(18)
    }
}
