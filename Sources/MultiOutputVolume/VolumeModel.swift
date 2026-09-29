import AppKit
import Combine
import Foundation

@MainActor
final class VolumeModel: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var airPlayDevices: [AirPlayDevice] = []
    @Published var selectedDeviceUIDs: Set<String>
    @Published var activeOutputUID: String?
    @Published var volume: Float
    @Published private(set) var outputBalance: Float
    @Published var isVolumeSliderDragging = false
    @Published private(set) var isMuted: Bool
    @Published private(set) var lastStatus: String = ""
    @Published private(set) var lastHotKeySource: String = "未触发"
    @Published private(set) var hotKeyEvents: [HotKeyEventRecord] = []
    @Published var launchAtLoginEnabled: Bool

    let preferredGroupName = "显示器 + 音箱"
    static let outputSelectionShowsHUD = false
    var hudAnchorProvider: (() -> NSRect?)?

    private let store: AudioDeviceStoring
    private let controller: SafeVolumeController
    private let defaults: UserDefaults
    private let ddc = DDCVolumeController()
    private let keyMonitor = MediaKeyMonitor()
    private let airPlayBrowser = AirPlayDeviceBrowser()
    private let hud = VolumeHUDController()
    private let volumeFeedback = VolumeFeedbackPlayer()
    private var refreshTimer: Timer?
    private var defaultOutputTimer: Timer?

    init(defaults: UserDefaults = .standard, store: AudioDeviceStoring = CoreAudioDeviceStore()) {
        self.defaults = defaults
        self.store = store
        let savedRestore = (defaults.dictionary(forKey: "restoreLevelsByUID") ?? [:])
            .compactMapValues { ($0 as? NSNumber)?.floatValue }
        self.controller = SafeVolumeController(restoreLevels: savedRestore)
        let savedUIDs = defaults.stringArray(forKey: "selectedDeviceUIDs") ?? []
        self.selectedDeviceUIDs = Set(savedUIDs)
        self.volume = 0
        self.isMuted = false
        self.outputBalance = min(max(defaults.float(forKey: "outputBalance"), -1), 1)
        self.launchAtLoginEnabled = LaunchAtLoginController.isEnabled
    }

    func start(enableHotKeys: Bool = true) {
        airPlayBrowser.onChange = { [weak self] devices in
            self?.airPlayDevices = devices
        }
        // Opt-in only: no unnecessary LAN discovery for local speaker/headphone control.
        if defaults.bool(forKey: "enableBonjourDiscovery") { airPlayBrowser.start() }
        refreshDevices()
        if enableHotKeys {
            keyMonitor.onAction = { [weak self] action, source in
                self?.handle(action, source: source)
            }
            keyMonitor.start()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDevices() }
        }
        defaultOutputTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncSelectionFromSystemOutput() }
        }
    }

    func stop() {
        keyMonitor.stop()
        airPlayBrowser.stop()
        refreshTimer?.invalidate()
        refreshTimer = nil
        defaultOutputTimer?.invalidate()
        defaultOutputTimer = nil
    }

    func refreshDevices() {
        devices = store.outputDevices()
        syncSelectionFromSystemOutput()
        syncVolumeFromSelectedDevices()
    }

    func toggleDevice(_ uid: String) {
        if selectedDeviceUIDs.contains(uid) {
            selectedDeviceUIDs.remove(uid)
        } else {
            selectedDeviceUIDs.insert(uid)
        }
        loadPairBalance()
        persist()
        syncVolumeFromSelectedDevices()
    }

    func selectOnly(_ uid: String) {
        guard let device = devices.first(where: { $0.uid == uid }) else { return }
        let complete = store.setDefaultOutput(deviceID: device.id)
        // Even a partial switch may have changed the normal output. Follow actual routing.
        syncSelectionFromSystemOutput()
        syncVolumeFromSelectedDevices()
        lastStatus = complete ? "已切换到 \(device.name)（输出及系统提示音均确认）"
            : "切换未全部成功：\(device.name)；请检查系统输出与提示音输出"
    }

    func selectPreferredGroup() {
        guard let aggregate = devices.first(where: \.isPreferredAggregateOutput) else { return }
        selectOnly(aggregate.uid)
    }

    func openAirPlayOutput(_ device: AirPlayDevice) {
        lastStatus = "请在系统声音设置中选择 \(device.name)"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func setUnifiedVolume(
        _ newValue: Float,
        showHUD: Bool = true,
        playFeedback: Bool = false
    ) {
        guard newValue.isFinite else { return }
        applyVolume(min(max(newValue, 0), 1), showHUD: showHUD)
        if playFeedback {
            volumeFeedback.play()
        }
    }

    func setOutputBalance(_ value: Float) {
        guard value.isFinite else { return }
        outputBalance = min(max(value, -1), 1)
        persist()
        if balanceDevices.count == 2 && !isMuted {
            applyVolume(volume, showHUD: false)
        }
    }

    static func balancedVolume(
        _ volume: Float,
        balance: Float,
        isDisplay: Bool
    ) -> Float {
        let balance = min(max(balance, -1), 1)
        let gain = isDisplay ? 1 - max(balance, 0) : 1 + min(balance, 0)
        return min(max(volume, 0), 1) * gain
    }

    private func deviceVolume(_ master: Float, for device: AudioDevice) -> Float {
        guard balanceDevices.count == 2 else { return master }
        return Self.balancedVolume(master, balance: outputBalance,
                                   isDisplay: device.uid == balanceDevices[0].uid)
    }

    func handle(_ action: VolumeKeyAction, source: VolumeKeySource? = nil) {
        refreshDevices() // Resolve routing and actual level before handling a native key.
        if let source {
            lastHotKeySource = source.rawValue
        }
        let showCustomHUD = Self.shouldShowCustomHUD(for: source)
        let playFeedback = Self.shouldPlayVolumeFeedback(for: source)
        switch action {
        case .mute:
            toggleMute(showHUD: showCustomHUD)
        case .decrease:
            setUnifiedVolume(
                volume - 0.0625,
                showHUD: showCustomHUD,
                playFeedback: playFeedback
            )
        case .increase:
            setUnifiedVolume(
                volume + 0.0625,
                showHUD: showCustomHUD,
                playFeedback: playFeedback
            )
        }
        if let source {
            recordHotKeyEvent(action: action, source: source)
        }
    }

    func runHotKeySelfTest() {
        handle(.increase, source: .selfTest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.handle(.decrease, source: .selfTest)
        }
    }

    func showHUDForCurrentVolume() {
        showHUD(volume: volume, isMuted: isMuted)
    }

    func playVolumeFeedback() {
        volumeFeedback.play()
    }

    func hotKeyDiagnostics() -> String {
        [
            "accessibilityTrusted=\(AXIsProcessTrusted())",
            "monitorAccessibilityTrusted=\(keyMonitor.accessibilityTrusted)",
            "eventTapCreated=\(keyMonitor.eventTapCreated)",
            "eventTapReceivedEvent=\(keyMonitor.eventTapReceivedEvent)",
            "globalMonitorCreated=\(keyMonitor.globalMonitorCreated)",
            "globalMonitorReceivedEvent=\(keyMonitor.globalMonitorReceivedEvent)",
            "carbonRegisteredIDs=\(keyMonitor.carbonRegisteredIDs.sorted())",
            "lastSource=\(keyMonitor.lastSource?.rawValue ?? "nil")"
        ].joined(separator: "\n")
    }

    func copyDiagnosticsToPasteboard() {
        refreshDevices()
        let selected = selectedDevices.map(\.name).joined(separator: ", ")
        let deviceLines = devices.map { device in
            "- \(device.name) | uid=\(device.uid) | kind=\(device.kind.rawValue) | canSetVolume=\(device.canSetVolume) | canSetMute=\(device.canSetMute)"
        }.joined(separator: "\n")
        let text = """
        VolX Diagnostics
        activeOutputUID=\(activeOutputUID ?? "nil")
        selectedDevices=\(selected)
        volume=\(Int((volume * 100).rounded()))%
        isMuted=\(isMuted)
        ddc=\(ddcStatusText)
        \(hotKeyDiagnostics())
        devices:
        \(deviceLines)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastStatus = "诊断信息已复制"
    }

    func toggleMute(showHUD: Bool = true) {
        syncVolumeFromSelectedDevices()
        let targets = controller.muteTargets(readSelectedLevels(), muted: !isMuted)
        applyTargets(targets, showHUD: showHUD)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            launchAtLoginEnabled = enabled
            lastStatus = enabled ? "已开启登录时启动" : "已关闭登录时启动"
        } catch {
            launchAtLoginEnabled = LaunchAtLoginController.isEnabled
            lastStatus = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    var selectedDevices: [AudioDevice] {
        devices.filter { selectedDeviceUIDs.contains($0.uid) }
    }

    var visibleOutputDevices: [AudioDevice] {
        devices
    }

    var visibleAirPlayDevices: [AirPlayDevice] {
        let localNames = Set(devices.map { normalizedDeviceName($0.name) })
        return airPlayDevices.filter { !localNames.contains(normalizedDeviceName($0.name)) }
    }

    var visibleOutputRowCount: Int {
        visibleOutputDevices.count + visibleAirPlayDevices.count
    }

    var isPreferredGroupSelected: Bool {
        let preferred = Set(devices.filter(\.isDefaultTarget).map(\.uid))
        return !preferred.isEmpty && selectedDeviceUIDs == preferred
    }

    var controlTitle: String {
        let selected = selectedDevices
        if isMultiOutputSelected {
            return devices.first(where: { $0.uid == activeOutputUID })?.name ?? "双设备输出"
        }
        return selected.first?.name ?? "统一音量"
    }

    var ddcStatusText: String {
        "本修复版已禁用 DDC：显示器音量不受支持；仅控制 CoreAudio 音箱/耳机"
    }

    static func shouldShowCustomHUD(for source: VolumeKeySource?) -> Bool {
        source != .globalMonitor
    }

    static func shouldPlayVolumeFeedback(for source: VolumeKeySource?) -> Bool {
        source != .globalMonitor
    }

    static func selectionForSystemOutput(uid: String, devices: [AudioDevice]) -> Set<String>? {
        AudioDevice.selectionForSystemOutput(uid: uid, devices: devices)
    }

    private func syncSelectionFromSystemOutput() {
        guard let systemUID = store.defaultOutputUID() else {
            activeOutputUID = nil
            selectedDeviceUIDs = []
            syncVolumeFromSelectedDevices()
            return
        }
        let outputChanged = activeOutputUID != systemUID
        let changedExternally = activeOutputUID != nil && activeOutputUID != systemUID
        activeOutputUID = systemUID

        guard let systemSelection = Self.selectionForSystemOutput(uid: systemUID, devices: devices) else {
            selectedDeviceUIDs = []
            syncVolumeFromSelectedDevices()
            return
        }
        guard outputChanged || selectedDeviceUIDs != systemSelection else { return }

        selectedDeviceUIDs = systemSelection
        loadPairBalance()
        persist()
        syncVolumeFromSelectedDevices()
        if changedExternally {
            let title = devices.first(where: { $0.uid == systemUID })?.name ?? "系统输出"
            lastStatus = "已跟随系统切换到 \(title)"
        }
    }

    private func readSelectedLevels() -> [DeviceLevel] {
        selectedDeviceUIDs.sorted().map { uid in
            guard let device = selectedDevices.first(where: { $0.uid == uid }) else {
                return DeviceLevel(uid: uid, volume: nil, muted: nil)
            }
            return DeviceLevel(uid: uid, volume: store.volume(deviceID: device.id),
                               muted: store.isMuted(deviceID: device.id))
        }
    }

    private func syncVolumeFromSelectedDevices() {
        controller.observe(readSelectedLevels())
        volume = controller.volume
        isMuted = controller.isMuted
    }

    private func applyVolume(_ newValue: Float, showHUD: Bool) {
        let targets = selectedDeviceUIDs.sorted().map { uid in
            let device = selectedDevices.first { $0.uid == uid }
            return DeviceTarget(uid: uid,
                                volume: device.map { deviceVolume(newValue, for: $0) } ?? newValue,
                                muted: false)
        }
        applyTargets(targets, showHUD: showHUD)
    }

    private func applyTargets(_ targets: [DeviceTarget], showHUD: Bool) {
        let outcomes = controller.apply(targets, write: { target in
            guard let device = self.selectedDevices.first(where: { $0.uid == target.uid }),
                  !device.isBenQDisplay else { return false }
            // Restore level while still hardware-muted, then unmute, never the reverse.
            let levelOK = self.store.setVolume(target.volume, deviceID: device.id)
            var muteOK = true
            if device.canSetMute {
                // A failed restore must not unmute an unexpectedly loud device.
                if target.muted || levelOK {
                    muteOK = self.store.setMuted(target.muted, deviceID: device.id)
                } else { muteOK = false }
            } else if !target.muted {
                muteOK = self.store.isMuted(deviceID: device.id) == false
            }
            return levelOK && muteOK
        }, read: { uid in
            guard let device = self.selectedDevices.first(where: { $0.uid == uid }) else {
                return DeviceLevel(uid: uid, volume: nil, muted: nil)
            }
            return DeviceLevel(uid: uid, volume: self.store.volume(deviceID: device.id),
                               muted: self.store.isMuted(deviceID: device.id))
        })
        volume = controller.volume
        isMuted = controller.isMuted
        let failures = outcomes.filter { !$0.confirmed }.map { outcome in
            selectedDevices.first(where: { $0.uid == outcome.uid })?.name ?? outcome.uid
        }
        if outcomes.isEmpty {
            lastStatus = "没有可控制的输出设备"
        } else if failures.isEmpty {
            lastStatus = "已确认 \(outcomes.count) 个设备\(isMuted ? "静音" : "音量")"
        } else {
            lastStatus = "部分/全部未确认：\(failures.joined(separator: "、"))；请检查实际声音（DDC 不支持）"
        }
        persist()
        if showHUD {
            // The HUD must carry failure text, not just a misleading mute glyph.
            hud.show(title: failures.isEmpty && !outcomes.isEmpty ? controlTitle : lastStatus,
                     volume: volume, isMuted: isMuted, anchorRect: hudAnchorProvider?())
        }
    }

    private func showHUD(volume: Float, isMuted: Bool) {
        hud.show(
            title: controlTitle,
            volume: volume,
            isMuted: isMuted,
            anchorRect: hudAnchorProvider?()
        )
    }

    private func recordHotKeyEvent(action: VolumeKeyAction, source: VolumeKeySource) {
        let record = HotKeyEventRecord(
            date: Date(),
            action: action,
            source: source,
            volume: volume,
            muted: isMuted,
            result: lastStatus
        )
        hotKeyEvents.insert(record, at: 0)
        if hotKeyEvents.count > 5 {
            hotKeyEvents.removeLast(hotKeyEvents.count - 5)
        }
        HotKeyEventLogger.append(record)
    }

    private func persist() {
        defaults.set(Array(selectedDeviceUIDs), forKey: "selectedDeviceUIDs")
        defaults.set(controller.restoreLevels, forKey: "restoreLevelsByUID")
        defaults.set(volume, forKey: "volume")
        defaults.set(isMuted, forKey: "isMuted")
        defaults.set(outputBalance, forKey: "outputBalance")
        if let pairKey {
            var balances = defaults.dictionary(forKey: "pairBalances") ?? [:]
            balances[pairKey] = outputBalance
            defaults.set(balances, forKey: "pairBalances")
        }
    }

    private func normalizedDeviceName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    var isMultiOutputSelected: Bool {
        devices.first(where: { $0.uid == activeOutputUID })?.kind == .aggregate
    }

    var balanceDevices: [AudioDevice] {
        guard isMultiOutputSelected, selectedDevices.count == 2 else { return [] }
        return selectedDevices.sorted { $0.uid < $1.uid }
    }

    private var pairKey: String? {
        guard balanceDevices.count == 2 else { return nil }
        return balanceDevices.map { "\($0.uid.count):\($0.uid)" }.joined()
    }

    private func loadPairBalance() {
        guard let pairKey else { outputBalance = 0; return }
        let balances = defaults.dictionary(forKey: "pairBalances")
        let stored = balances?[pairKey] as? NSNumber
        let savedSelection = Set(defaults.stringArray(forKey: "selectedDeviceUIDs") ?? [])
        let legacy = balances == nil && savedSelection == selectedDeviceUIDs
            ? defaults.float(forKey: "outputBalance") : 0
        outputBalance = min(max(stored?.floatValue ?? legacy, -1), 1)
    }
}
