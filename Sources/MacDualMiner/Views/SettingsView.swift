import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            CPUSettings().tabItem { Label("CPU · Monero", systemImage: "cpu") }
            GPUSettings().tabItem { Label("GPU · Ravencoin", systemImage: "square.stack.3d.up") }
            RulesSettings().tabItem { Label("Rules", systemImage: "slider.horizontal.3") }
            EarningsSettings().tabItem { Label("Earnings", systemImage: "dollarsign.circle") }
        }
        .padding(8)
    }
}

private struct CPUSettings: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.store
        let cores = coordinator.hardware.totalCores
        Form {
            Section {
                Toggle("Mine Monero on the CPU", isOn: $store.settings.cpuEnabled)
                TextField("Monero wallet address", text: $store.settings.xmrWallet, prompt: Text("4… or 8… (95 characters)"))
                    .textFieldStyle(.roundedBorder)
                validity(store.settings.xmrWallet, valid: WalletValidator.isMonero(store.settings.xmrWallet))
                TextField("Worker name", text: $store.settings.workerName)
            }
            Section("Pool") {
                TextField("Pool host:port", text: $store.settings.xmrPool)
                Toggle("Use TLS", isOn: $store.settings.xmrPoolTLS)
                HStack {
                    Text("Pool fee")
                    Spacer()
                    TextField("", value: $store.settings.xmrPoolFeePercent, format: .number).frame(width: 60)
                    Text(verbatim: "%")
                }
                Text(verbatim: "Default is SupportXMR (0.6% fee, port 443 with TLS). Any Monero stratum pool works.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Performance – \(cores) cores detected") {
                Picker("Threads", selection: $store.settings.cpuPreset) {
                    ForEach(CPUPreset.allCases) { preset in
                        if let n = preset.threads(totalCores: cores, custom: store.settings.cpuCustomThreads), preset != .custom {
                            Text("\(preset.label) (\(n))").tag(preset)
                        } else {
                            Text(preset.label).tag(preset)
                        }
                    }
                }
                if store.settings.cpuPreset == .custom {
                    Stepper("Custom threads: \(store.settings.cpuCustomThreads)",
                            value: $store.settings.cpuCustomThreads, in: 1...max(1, cores))
                }
                Picker("Priority", selection: $store.settings.cpuPriority) {
                    Text("Idle (0)").tag(0)
                    Text("Low (1)").tag(1)
                    Text("Normal (2)").tag(2)
                    Text("High (3)").tag(3)
                }
                Toggle("Yield to other apps", isOn: $store.settings.cpuYield)
                Text("RandomX wants ~2 MB of cache per thread, so on the M5 Max \"Balanced\" often matches \"Full\" in hashrate with less heat – especially while the GPU is also mining. Changes apply automatically (XMRig restarts).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GPUSettings: View {
    @Environment(MiningCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var store = coordinator.store
        Form {
            Section {
                Toggle("Mine Ravencoin on the GPU (Metal)", isOn: $store.settings.gpuEnabled)
                TextField("Ravencoin wallet address", text: $store.settings.rvnWallet, prompt: Text("R… (34 characters)"))
                    .textFieldStyle(.roundedBorder)
                validity(store.settings.rvnWallet, valid: WalletValidator.isRavencoin(store.settings.rvnWallet))
            }
            Section("Pool") {
                TextField("Pool host:port", text: $store.settings.rvnPool)
                HStack {
                    Text("Pool fee")
                    Spacer()
                    TextField("", value: $store.settings.rvnPoolFeePercent, format: .number).frame(width: 60)
                    Text(verbatim: "%")
                }
                Text("kawpow-metal speaks plain (non-TLS) stratum. Worker is sent as ADDRESS.\(coordinator.settings.workerName). On first start it builds the epoch's light cache and a multi-GB DAG on the GPU, which takes about a minute.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RulesSettings: View {
    @Environment(MiningCoordinator.self) private var coordinator
    @State private var loginError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var store = coordinator.store
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
                Toggle("Open MacDualMiner at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = "Couldn't change login item: \(error.localizedDescription). Move the app to /Applications first."
                        }
                    }
                if let loginError {
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
