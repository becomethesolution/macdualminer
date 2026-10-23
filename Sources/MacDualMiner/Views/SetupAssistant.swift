import SwiftUI

/// First-run setup: electricity price → where to get paid → benchmark. Opens by itself the first time the
/// app runs with nowhere to be paid set up; Settings › General › Setup assistant opens it again.
/// (No @State – view state lives in UIState so Command Line Tools builds work; see UIState.)
struct SetupAssistant: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UIState.self) private var uiState

    private let titles = ["Your electricity price", "Where to get paid", "Measure this Mac"]

    var body: some View {
        let step = min(max(uiState.setupStep, 0), titles.count - 1)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(titles[step]).font(.title2.bold())
                Spacer()
                Text("Step \(step + 1) of \(titles.count)").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                Group {
                    switch step {
                    case 0: electricity
                    case 1: payout
                    default: benchmark
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Set up later") { finish() }
                    .help("Close the assistant. Everything here is also in Settings, and Settings › General can open it again.")
                Spacer()
                if step > 0 {
                    Button("Back") { uiState.setupStep = step - 1 }
                }
                if step < titles.count - 1 {
                    Button("Next") { uiState.setupStep = step + 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { finish() }
                    Button("Benchmark now") {
                        finish()
                        uiState.mainTab = .profit
                        coordinator.runBenchmark()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!coordinator.settings.canMineSomething)
                }
            }
        }
        .padding(24)
        .frame(width: 580)
        .frame(minHeight: 460)
    }

    private var electricity: some View {
        @Bindable var store = coordinator.store
        return VStack(alignment: .leading, spacing: 12) {
            Text("Mining profit is what the coins are worth minus the electricity the Mac uses, so the price you pay matters more than anything else.")
            HStack {
                Text("Price per kWh (USD)")
                TextField("", value: $store.settings.electricityUSDPerKWh, format: .number.precision(.fractionLength(2...4)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
            }
            Text("Use the total from your bill – supply plus delivery – divided by the kWh used. Use 0 if you don't pay for electricity where the Mac runs.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var payout: some View {
        @Bindable var store = coordinator.store
        @Bindable var ui = uiState
        let xmrWallet = Binding<String>(
            get: { store.settings.wallet(for: "XMR") },
            set: { store.settings.wallets["XMR"] = $0; store.settings.xmrWallet = $0 })
        let rvnWallet = Binding<String>(
            get: { store.settings.wallet(for: "RVN") },
            set: { store.settings.wallets["RVN"] = $0; store.settings.rvnWallet = $0 })
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Get paid", selection: $ui.setupPayout) {
                ForEach(SetupPayout.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch ui.setupPayout {
            case .unmineable:
                Text("Your Mac mines Monero on the CPU and unMineable pays you in a coin your wallet already holds – Dogecoin, Litecoin, Bitcoin and others. Good for Trust Wallet, which has no Monero.")
                    .font(.callout)
                Form { UnmineablePayoutFields() }
                    .formStyle(.columns)
            case .wallet:
                Text("Paste a receiving address for each coin you want to mine. You can add more coins later in Settings › Coins & Wallets.")
                    .font(.callout)
                TextField("Monero (XMR) wallet – CPU", text: xmrWallet, prompt: Text("4… or 8… (95 characters)"))
                    .textFieldStyle(.roundedBorder)
                TextField("Ravencoin (RVN) wallet – GPU, optional", text: rvnWallet, prompt: Text("R… (34 characters)"))
                    .textFieldStyle(.roundedBorder)
            case .kryptex:
                Text("One Kryptex username covers every coin on a Kryptex pool (Monero, Zephyr, EthereumPoW, Quai). Kryptex can convert earnings to Bitcoin for you.")
                    .font(.callout)
                TextField("Kryptex username", text: $store.settings.kryptexAccount, prompt: Text("your Kryptex username"))
                    .textFieldStyle(.roundedBorder)
            }
            if !store.settings.canMineSomething {
                Text("Nothing can be mined until this is filled in.").font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Ready to mine", systemImage: "checkmark.circle").font(.caption).foregroundStyle(Theme.profit)
            }
        }
        // The tab picks how Monero (the CPU coin) is paid, so what's entered here makes a coin ready.
        // Re-running setup starts on the tab that matches the current setup and changes nothing by itself.
        .onAppear {
            if store.settings.hasPayoutDestination { ui.setupPayout = currentPayoutChoice() }
            else { applyPayoutChoice(ui.setupPayout) }
        }
        .onChange(of: ui.setupPayout) { _, choice in applyPayoutChoice(choice) }
    }

    private func currentPayoutChoice() -> SetupPayout {
        switch coordinator.settings.poolChoice["XMR"] {
        case "unmineable": return .unmineable
        case "kryptex": return .kryptex
        default: return .wallet
        }
    }

    private func applyPayoutChoice(_ choice: SetupPayout) {
        guard choice != currentPayoutChoice() else { return }   // also keeps a custom Monero pool
        let settings = coordinator.store
        switch choice {
        case .unmineable: settings.settings.poolChoice["XMR"] = "unmineable"
        case .wallet: settings.settings.poolChoice["XMR"] = nil          // SupportXMR, the default
        case .kryptex: settings.settings.poolChoice["XMR"] = "kryptex"
        }
    }

    private var benchmark: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The benchmark runs each engine for about two minutes on its own, so Profit Check ranks coins with this Mac's real hashrate and power instead of reference numbers.")
            Text("Your Mac gets warm and its fans may spin up while it runs. You can skip an engine or cancel at any time on the Profit Check tab.")
                .font(.callout).foregroundStyle(.secondary)
            if !coordinator.settings.canMineSomething {
                Label("Add somewhere to get paid first (step 2) – the benchmark mines real shares.", systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(Theme.accent)
            }
            Text("Mining wears hardware over time and may not be profitable where you live. See the disclaimer on the Dashboard.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func finish() {
        coordinator.store.settings.setupCompleted = true
        uiState.showSetup = false
        uiState.setupStep = 0
    }
}
