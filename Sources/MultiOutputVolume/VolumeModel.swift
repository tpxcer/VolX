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
    @Published var isVolumeSliderDragging = false
    @Published private(set) var isMuted: Bool
    @Published private(set) var lastStatus: String = ""
    @Published private(set) var lastHotKeySource: String = "未触发"
    @Published private(set) var hotKeyEvents: [HotKeyEventRecord] = []
    @Published var launchAtLoginEnabled: Bool

    let preferredGroupName = "显示器 + 音箱"
    static let outputSelectionShowsHUD = false
    var hudAnchorProvider: (() -> NSRect?)?

    private let store = CoreAudioDeviceStore()
    private let ddc = DDCVolumeController()
    private let keyMonitor = MediaKeyMonitor()
    private let airPlayBrowser = AirPlayDeviceBrowser()
    private let hud = VolumeHUDController()
    private let volumeFeedback = VolumeFeedbackPlayer()
    private var refreshTimer: Timer?
    private var defaultOutputTimer: Timer?
    private var rememberedVolumeBeforeMute: Float = 0.27

    init() {
        let defaults = UserDefaults.standard
        let savedUIDs = defaults.stringArray(forKey: "selectedDeviceUIDs") ?? []
        self.selectedDeviceUIDs = Set(savedUIDs)
        let savedVolume = defaults.object(forKey: "volume") as? Float ?? 0.27
        self.volume = min(max(savedVolume, 0), 1)
        self.isMuted = defaults.bool(forKey: "isMuted")
        self.launchAtLoginEnabled = LaunchAtLoginController.isEnabled
    }

    func start(enableHotKeys: Bool = true) {
        airPlayBrowser.onChange = { [weak self] devices in
            self?.airPlayDevices = devices
        }
        airPlayBrowser.start()
        refreshDevices()
        activatePreferredAggregateIfNeeded()
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
        applyVolume(volume, showHUD: Self.outputSelectionShowsHUD)
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
        let availableUIDs = Set(devices.map(\.uid))
        selectedDeviceUIDs = Set(selectedDeviceUIDs.filter { availableUIDs.contains($0) })
        syncSelectionFromSystemOutput()
        if selectedDeviceUIDs.isEmpty {
            let preferred = devices.filter(\.isDefaultTarget)
            selectedDeviceUIDs = Set(preferred.map(\.uid))
            persist()
        }
        syncVolumeFromSelectedDevices()
    }

    func toggleDevice(_ uid: String) {
        if selectedDeviceUIDs.contains(uid) {
            selectedDeviceUIDs.remove(uid)
        } else {
            selectedDeviceUIDs.insert(uid)
        }
        persist()
        activatePreferredAggregateIfNeeded()
        applyVolume(volume, showHUD: false)
    }

    func selectOnly(_ uid: String) {
        selectedDeviceUIDs = [uid]
        persist()
        if let device = devices.first(where: { $0.uid == uid }) {
            if store.setDefaultOutput(deviceID: device.id) {
                activeOutputUID = device.uid
                lastStatus = "已切换到 \(device.name)"
            } else {
                lastStatus = "切换到 \(device.name) 失败"
            }
        }
        applyVolume(
            volume,
            showHUD: Self.outputSelectionShowsHUD,
            preserveStatus: true
        )
    }

    func selectPreferredGroup() {
        let targets = Set(devices.filter(\.isDefaultTarget).map(\.uid))
        selectedDeviceUIDs = targets
        persist()
        if targets.isEmpty {
            lastStatus = "未找到 BenQ 和音箱"
        } else if activatePreferredAggregateIfNeeded() {
            lastStatus = "已恢复双输出"
        } else {
            lastStatus = "未找到系统多输出设备"
        }
        applyVolume(
            volume,
            showHUD: Self.outputSelectionShowsHUD,
            preserveStatus: true
        )
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
        isMuted = false
        volume = min(max(newValue, 0), 1)
        persist()
        applyVolume(volume, showHUD: showHUD)
        if playFeedback {
            volumeFeedback.play()
        }
    }

    func handle(_ action: VolumeKeyAction, source: VolumeKeySource? = nil) {
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
        isMuted.toggle()
        if isMuted {
            rememberedVolumeBeforeMute = max(volume, 0.01)
        } else if volume <= 0.001 {
            volume = rememberedVolumeBeforeMute
        }
        persist()
        applyMute(isMuted, showHUD: showHUD)
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
        devices.filter { !$0.isPreferredAggregateOutput }
    }

    var visibleAirPlayDevices: [AirPlayDevice] {
        let localNames = Set(devices.map { normalizedDeviceName($0.name) })
        return airPlayDevices.filter { !localNames.contains(normalizedDeviceName($0.name)) }
    }

    var visibleOutputRowCount: Int {
        visibleOutputDevices.count + visibleAirPlayDevices.count + 1
    }

    var isPreferredGroupSelected: Bool {
        let preferred = Set(devices.filter(\.isDefaultTarget).map(\.uid))
        return !preferred.isEmpty && selectedDeviceUIDs == preferred
    }

    var controlTitle: String {
        let selected = selectedDevices
        if selected.count >= 2 {
            return preferredGroupName
        }
        return selected.first?.name ?? "统一音量"
    }

    var ddcStatusText: String {
        ddc.isAvailable ? "DDC 后端已找到" : "未找到 ddcctl/m1ddc，BenQ 暂不能由本工具直接写入音量"
    }

    static func shouldShowCustomHUD(for source: VolumeKeySource?) -> Bool {
        source != .globalMonitor
    }

    static func shouldPlayVolumeFeedback(for source: VolumeKeySource?) -> Bool {
        source != .globalMonitor
    }

    static func selectionForSystemOutput(
        uid: String,
        devices: [AudioDevice]
    ) -> Set<String>? {
        guard let output = devices.first(where: { $0.uid == uid }) else { return nil }
        if output.isPreferredAggregateOutput {
            return Set(devices.filter(\.isDefaultTarget).map(\.uid))
        }
        return [output.uid]
    }

    private func syncSelectionFromSystemOutput() {
        guard let systemUID = store.defaultOutputUID() else { return }
        let changedExternally = activeOutputUID != nil && activeOutputUID != systemUID
        activeOutputUID = systemUID

        guard let systemSelection = Self.selectionForSystemOutput(uid: systemUID, devices: devices),
              selectedDeviceUIDs != systemSelection else {
            return
        }

        selectedDeviceUIDs = systemSelection
        persist()
        syncVolumeFromSelectedDevices()
        if changedExternally {
            let title = devices.first(where: { $0.uid == systemUID })?.name ?? "系统输出"
            lastStatus = "已跟随系统切换到 \(title)"
        }
    }

    private func syncVolumeFromSelectedDevices() {
        let readable = selectedDevices.compactMap { store.volume(deviceID: $0.id) }
        guard !readable.isEmpty else { return }
        volume = readable.reduce(0, +) / Float(readable.count)
    }

    @discardableResult
    private func activatePreferredAggregateIfNeeded() -> Bool {
        guard selectedDevices.count >= 2,
              let aggregate = devices.first(where: \.isPreferredAggregateOutput) else {
            return false
        }
        if store.setDefaultOutput(deviceID: aggregate.id) {
            activeOutputUID = aggregate.uid
            return true
        }
        return false
    }

    private func applyVolume(_ newValue: Float, showHUD: Bool, preserveStatus: Bool = false) {
        var changed = 0
        for device in selectedDevices {
            if device.isBenQDisplay {
                if ddc.setVolume(newValue, for: device) { changed += 1 }
            } else {
                _ = store.setMuted(false, deviceID: device.id)
                if store.setVolume(newValue, deviceID: device.id) {
                    changed += 1
                }
            }
        }
        if !preserveStatus {
            lastStatus = changed > 0 ? "已同步 \(changed) 个设备音量" : ddcStatusText
        }
        if showHUD {
            self.showHUD(volume: newValue, isMuted: isMuted)
        }
    }

    private func applyMute(_ muted: Bool, showHUD: Bool) {
        var changed = 0
        let restore = max(rememberedVolumeBeforeMute, 0.01)
        for device in selectedDevices {
            if device.isBenQDisplay {
                if ddc.setMuted(muted, for: device, restoreVolume: restore) { changed += 1 }
            } else if store.setMuted(muted, deviceID: device.id) {
                changed += 1
            } else if store.setVolume(muted ? 0 : restore, deviceID: device.id) {
                changed += 1
            }
        }
        if muted {
            volume = 0
        } else {
            volume = restore
        }
        lastStatus = changed > 0 ? "已同步 \(changed) 个设备静音状态" : ddcStatusText
        if showHUD {
            self.showHUD(volume: volume, isMuted: muted)
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
        let defaults = UserDefaults.standard
        defaults.set(Array(selectedDeviceUIDs), forKey: "selectedDeviceUIDs")
        defaults.set(volume, forKey: "volume")
        defaults.set(isMuted, forKey: "isMuted")
    }

    private func normalizedDeviceName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
