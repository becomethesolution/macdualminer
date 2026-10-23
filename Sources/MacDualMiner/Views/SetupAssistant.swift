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
            Group {
                switch step {
                case 0: electricity
                case 1: payout
                default: benchmark
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
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
                    .disabled(!coordinator.settings.hasPayoutDestination)
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 430)
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
        let viaUnmineable = Binding<Bool>(
            get: { store.settings.poolChoice["XMR"] == "unmineable" },
            set: { store.settings.poolChoice["XMR"] = $0 ? "unmineable" : nil })
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
                Toggle("Mine Monero through unMineable", isOn: viaUnmineable)
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
            if !store.settings.hasPayoutDestination {
                Text("Nothing can be mined until one of these is filled in.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var benchmark: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The benchmark runs each engine for about two minutes on its own, so Profit Check ranks coins with this Mac's real hashrate and power instead of reference numbers.")
            Text("Your Mac gets warm and its fans may spin up while it runs. You can skip an engine or cancel at any time on the Profit Check tab.")
                .font(.callout).foregroundStyle(.secondary)
            if !coordinator.settings.hasPayoutDestination {
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
