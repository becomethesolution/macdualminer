import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            CoinsSettings().tabItem { Label("Coins & Wallets", systemImage: "bitcoinsign.circle") }
            SwitchingSettings().tabItem { Label("Switching", systemImage: "arrow.triangle.2.circlepath") }
            EngineSettings().tabItem { Label("Engines", systemImage: "cpu") }
            RulesSettings().tabItem { Label("Rules", systemImage: "slider.horizontal.3") }
            EarningsSettings().tabItem { Label("Earnings", systemImage: "dollarsign.circle") }
        }
        .padding(8)
    }
}

private struct GeneralSettings: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UpdateService.self) private var updates

    var body: some View {
        @Bindable var store = coordinator.store
        Form {
            Section("Appearance") {
                Toggle("Dark mining-dashboard look (off = follow macOS)", isOn: $store.settings.darkInterface)
            }
            Section("Updates") {
                Toggle("Check GitHub for new versions automatically", isOn: $store.settings.checkForUpdates)
                HStack {
                    Text("You have MacDualMiner \(updates.currentVersion)")
                    Spacer()
                    Button("Check now") { Task { await updates.check() } }
                        .disabled(updates.state == .checking)
                }
                switch updates.state {
                case .idle: EmptyView()
                case .checking: Text("Checking…").font(.caption).foregroundStyle(.secondary)
                case .upToDate: Label("You're up to date", systemImage: "checkmark.circle").font(.caption).foregroundStyle(Theme.profit)
                case .available(let info):
                    HStack {
                        Label("Version \(info.version) is available", systemImage: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
                        Spacer()
                        Button("Release notes") { updates.openReleasePage() }
                        Button("Install & Restart") { Task { await updates.installUpdate { coordinator.shutdown() } } }
                            .buttonStyle(.borderedProminent)
                    }
                case .downloading(let what): Text(what).font(.caption)
                case .failed(let why): Text(why).font(.caption).foregroundStyle(Theme.loss)
                }
                if let checked = updates.lastChecked {
                    Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened)) · github.com/\(UpdateService.repository)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Updates are downloaded from this app's GitHub releases, checked for the right app, version and code signature, then swapped in and the app restarts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// One row per coin: algorithm, engines, wallet and pool.
private struct CoinsSettings: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.store
        Form {
            Section {
                TextField("Worker name", text: $store.settings.workerName, prompt: Text(HardwareInfo.current.defaultWorkerName))
                TextField("Kryptex account (username)", text: $store.settings.kryptexAccount, prompt: Text("optional"))
                Text("Coins on a Kryptex pool with no wallet of their own are paid to this Kryptex account, which can auto-convert to BTC (not QUAI). Use your Kryptex username rather than an email for ethminer and UselethMiner.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Algorithm.allCases) { algorithm in
                Section("\(algorithm.rawValue) – " + engines(for: algorithm)) {
                    ForEach(CoinCatalog.coins.filter { $0.algorithm == algorithm }) { coin in
                        CoinRow(coin: coin)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func engines(for algorithm: Algorithm) -> String {
        EngineKind.allCases.filter { $0.algorithms.contains(algorithm) }
            .map { "\($0.displayName) (\($0.deviceLabel))" }.joined(separator: ", ")
    }
}

private struct CoinRow: View {
    @Environment(MiningCoordinator.self) private var coordinator
    let coin: CoinSpec

    var body: some View {
        @Bindable var store = coordinator.store
        let tag = coin.tag
        let wallet = Binding<String>(
            get: { store.settings.wallet(for: tag) },
            set: { newValue in
                store.settings.wallets[tag] = newValue
                if tag == "XMR" { store.settings.xmrWallet = newValue }
                if tag == "RVN" { store.settings.rvnWallet = newValue }
            })
        let poolChoice = Binding<String>(
            get: { store.settings.poolChoice[tag] ?? (coin.pools.first?.id ?? "custom") },
            set: { store.settings.poolChoice[tag] = $0 })
        let custom = Binding<CustomPool>(
            get: { store.settings.customPools[tag] ?? CustomPool() },
            set: { store.settings.customPools[tag] = $0 })

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(coin.name) (\(tag))").font(.headline)
                if coin.experimental { Text("beta").font(.caption2).padding(.horizontal, 4).background(.orange.opacity(0.2), in: Capsule()) }
                Spacer()
                if let problem = store.settings.readinessProblem(MiningOption(engine: coin.engines[0], coinTag: tag)) {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Ready", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
                }
            }
            TextField("\(tag) wallet", text: wallet, prompt: Text(coin.walletHint))
                .textFieldStyle(.roundedBorder)
            if let ok = WalletValidator.check(tag: tag, address: wallet.wrappedValue) {
                Label(ok ? "Address format looks right" : "That doesn't look like a valid \(tag) address",
                      systemImage: ok ? "checkmark.circle" : "xmark.octagon")
                    .font(.caption).foregroundStyle(ok ? Color.green : Color.red)
            }
            Picker("Pool", selection: poolChoice) {
                ForEach(coin.pools) { pool in
                    Text(verbatim: "\(pool.name) – \(pool.address)\(pool.tls ? " (TLS)" : "") · \(pool.feePercent.formatted())% fee").tag(pool.id)
                }
                Text("Custom…").tag("custom")
            }
            if poolChoice.wrappedValue == "custom" || coin.pools.isEmpty {
                HStack {
                    TextField("host:port", text: custom.address)
                    Toggle("TLS", isOn: custom.tls).toggleStyle(.checkbox)
                    TextField("Fee %", value: custom.feePercent, format: .number).frame(width: 60)
                }
                TextField("Login format", text: custom.userTemplate, prompt: Text("{wallet}.{worker}"))
                Text("Use {wallet} and {worker}. Most pools take {wallet}.{worker}; Kryptex takes {wallet}/{worker}.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let note = coin.note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 4)
    }
}

private struct SwitchingSettings: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.store
        let cpuOptions = MiningOption.all.filter { $0.engine.devices.contains(.cpu) }
        let gpuOptions = MiningOption.all.filter { $0.engine.devices.contains(.gpu) }
        Form {
            Section {
                Picker("Mode", selection: $store.settings.switchingMode) {
                    ForEach(SwitchingMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }
            Section("Manual / recommend-mode coins") {
                Picker("CPU", selection: $store.settings.manualCPUOption) {
                    ForEach(cpuOptions) { Text($0.label).tag($0.id) }
                }
                Picker("GPU", selection: $store.settings.manualGPUOption) {
                    ForEach(gpuOptions) { Text($0.label).tag($0.id) }
                }
                Text("UselethMiner uses the CPU and GPU together – picking it for either one runs it alone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Auto-switch rules") {
                Stepper("Check every \(store.settings.switchCheckMinutes) min", value: $store.settings.switchCheckMinutes, in: 5...240, step: 5)
                HStack {
                    Text("Only switch if at least")
                    TextField("", value: $store.settings.switchMarginPercent, format: .number).frame(width: 50)
                    Text(verbatim: "% more profitable")
                }
                Stepper("Keep a coin at least \(store.settings.minimumRunMinutes) min", value: $store.settings.minimumRunMinutes, in: 0...720, step: 5)
                HStack {
                    Text("Skip coins with under")
                    TextField("", value: $store.settings.minimumLiquidityBTC, format: .number).frame(width: 60)
                    Text("BTC of 24h trading volume")
                }
                Toggle("Use 24-hour averages (steadier than live values)", isOn: $store.settings.useDayAverages)
                Toggle("Pause a device when every coin on it would lose money after electricity", isOn: $store.settings.pauseUnprofitable)
                Text("Every switch on the GPU rebuilds a multi-GB DAG (about a minute of no hashing), so the margin and minimum run time stop it flip-flopping between coins that are almost equal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct EngineSettings: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.store
        let cores = coordinator.hardware.totalCores
        Form {
            Section("Parts of the chip") {
                Toggle("Mine on the CPU", isOn: $store.settings.cpuEnabled)
                Toggle("Mine on the GPU", isOn: $store.settings.gpuEnabled)
            }
            Section("Engines") {
                ForEach(EngineKind.allCases) { kind in
                    let installed = FileManager.default.isExecutableFile(atPath: kind.executable.path)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(kind.displayName) – \(kind.algorithms.map(\.rawValue).joined(separator: ", ")) on \(kind.deviceLabel) (\(kind.backend))")
                            Text(verbatim: engineNote(kind) + (installed ? "" : " · not installed"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if kind == .ethminer {
                            Toggle("", isOn: $store.settings.ethminerEnabled).labelsHidden()
                        } else if kind == .useleth {
                            Toggle("", isOn: $store.settings.uselethEnabled).labelsHidden()
                        }
                    }
                }
            }
            Section("Power rating") {
                PowerLevelControl(device: .cpu)
                PowerLevelControl(device: .gpu)
                Text("CPU: sets how many cores mine. GPU: sets how much of each second the GPU engine runs; it is paused in between. UselethMiner uses both: its CPU threads follow the CPU level and the GPU level paces the whole process.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("XMRig") {
                Picker("Priority", selection: $store.settings.cpuPriority) {
                    Text("Idle (0)").tag(0)
                    Text("Low (1)").tag(1)
                    Text("Normal (2)").tag(2)
                    Text("High (3)").tag(3)
                }
                Toggle("Yield to other apps", isOn: $store.settings.cpuYield)
            }
            Section("UselethMiner") {
                let installer = coordinator.uselethInstaller
                HStack {
                    Text(installer.isInstalled ? "Installed (v\(UselethInstaller.version))" : "Not installed")
                    Spacer()
                    if installer.isWorking {
                        ProgressView().controlSize(.small)
                    } else if installer.isInstalled {
                        Button("Remove") { installer.uninstall() }
                    } else {
                        Button("Download & install") { Task { await installer.install() } }
                    }
                }
                Text("Closed-source freeware by Chainfire, so it isn't bundled. This downloads v\(UselethInstaller.version) from github.com/Chainfire/UselethMiner, checks its SHA-256 and unpacks it into the app's own folder – no admin password, nothing system-wide.")
                    .font(.caption).foregroundStyle(.secondary)
                if let status = installer.status { Text(status).font(.caption) }
                Stepper(store.settings.uselethThreads == 0 ? "CPU threads: one per core (\(cores))" : "CPU threads: \(store.settings.uselethThreads)",
                        value: $store.settings.uselethThreads, in: 0...max(1, cores * 2))
                Text("Needs about 7 GB of free RAM and twice the DAG size free on disk (it stores the DAG in ~/.uselethminer). Only EthereumPoW works – it can't load other Ethash chains' DAGs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func engineNote(_ kind: EngineKind) -> String {
        switch kind {
        case .xmrig: return "Open source (GPL-3) · 1% dev donation"
        case .kawpow: return "Open source (MIT) · no fee · plain stratum only"
        case .ethminer: return "Open source (GPL-3) · no fee · OpenCL"
        case .useleth: return "Closed source freeware · 1% dev fee · no TLS"
        }
    }
}

private struct RulesSettings: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @Environment(UIState.self) private var uiState

    var body: some View {
        @Bindable var store = coordinator.store
        @Bindable var ui = uiState
        Form {
            Section("When to mine") {
                Toggle("Pause on battery power", isOn: $store.settings.pauseOnBattery)
                Toggle("Pause under serious thermal pressure", isOn: $store.settings.pauseOnThermalPressure)
                Toggle("Only mine while I'm away", isOn: $store.settings.idleOnly)
                if store.settings.idleOnly {
                    Stepper("Start after \(store.settings.idleMinutes) min without keyboard/mouse",
                            value: $store.settings.idleMinutes, in: 1...120)
                }
                Toggle("Keep the Mac awake while mining", isOn: $store.settings.preventSleep)
            }
            Section("Startup") {
                Toggle("Start mining when the app opens", isOn: $store.settings.startMiningOnLaunch)
                Toggle("Open MacDualMiner at login", isOn: $ui.launchAtLogin)
                    .onChange(of: ui.launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            uiState.loginError = nil
                        } catch {
                            uiState.loginError = "Couldn't change login item: \(error.localizedDescription). Move the app to /Applications first."
                        }
                    }
                if let loginError = ui.loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct EarningsSettings: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.store
        Form {
            Section("Electricity") {
                HStack {
                    Text("Price per kWh (USD)")
                    Spacer()
                    TextField("", value: $store.settings.electricityUSDPerKWh, format: .number.precision(.fractionLength(2...4))).frame(width: 80)
                }
                Picker("Power figure", selection: $store.settings.powerSource) {
                    ForEach(PowerSourceMode.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("CPU mining estimate")
                    Spacer()
                    TextField("", value: $store.settings.cpuWattsEstimate, format: .number).frame(width: 60)
                    Text("W")
                }
                HStack {
                    Text("GPU mining estimate")
                    Spacer()
                    TextField("", value: $store.settings.gpuWattsEstimate, format: .number).frame(width: 60)
                    Text("W")
                }
                Text("Use the rate from your electric bill (supply + delivery). Measured modes read the Mac's own power sensor; the estimates are used to split it between CPU and GPU, or alone if no sensor is available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Fees") {
                HStack {
                    Text("XMRig dev donation")
                    Spacer()
                    TextField("", value: $store.settings.xmrDevFeePercent, format: .number).frame(width: 60)
                    Text(verbatim: "%")
                }
                Text(verbatim: "Official XMRig builds donate a minimum of 1% of hashing time.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Network data (advanced)") {
                TextField("Monero node JSON-RPC (fallback)", text: $store.settings.xmrNodeURL)
                TextField("Custom Ravencoin stats URL (optional)", text: $store.settings.customRVNStatsURL)
                HStack {
                    Text("Manual XMR difficulty (0 = live)")
                    Spacer()
                    TextField("", value: $store.settings.xmrDifficultyOverride, format: .number).frame(width: 150)
                }
                HStack {
                    Text("Manual RVN difficulty (0 = live)")
                    Spacer()
                    TextField("", value: $store.settings.rvnDifficultyOverride, format: .number).frame(width: 150)
                }
                Stepper("Refresh every \(store.settings.marketRefreshSeconds)s",
                        value: $store.settings.marketRefreshSeconds, in: 30...900, step: 30)
            }
        }
        .formStyle(.grouped)
    }
}

@ViewBuilder
private func validity(_ address: String, valid: Bool) -> some View {
    if address.isEmpty {
        Text("Required to mine. Paste the receiving address from your own wallet.").font(.caption).foregroundStyle(.secondary)
    } else if valid {
        Label("Address format looks right", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
    } else {
        Label("That doesn't look like a valid address", systemImage: "xmark.octagon").font(.caption).foregroundStyle(.red)
    }
}

/// 1–10 power rating for one part of the chip, with what it means in plain numbers.
struct PowerLevelControl: View {
    @Environment(MiningCoordinator.self) private var coordinator
    let device: Device
    var compact = false

    var body: some View {
        @Bindable var store = coordinator.store
        let level = device == .cpu ? $store.settings.cpuPowerLevel : $store.settings.gpuPowerLevel
        let value = Binding<Double>(get: { Double(level.wrappedValue) }, set: { level.wrappedValue = Int($0.rounded()) })
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(device.label) power")
                Slider(value: value, in: 1...10, step: 1)
                Text("\(level.wrappedValue)/10").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            if !compact {
                Text(detail(level.wrappedValue)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func detail(_ level: Int) -> String {
        let cores = coordinator.hardware.totalCores
        switch device {
        case .cpu:
            let threads = coordinator.settings.cpuThreads(totalCores: cores)
            return "\(threads) of \(cores) cores mining" + (level >= 9 ? " – hottest, loudest" : level <= 3 ? " – quiet, light load" : "")
        case .gpu:
            return level == 10 ? "GPU mines continuously" : "GPU mines \(level * 10)% of the time (\(level * 100) ms of every second)"
        }
    }
}
