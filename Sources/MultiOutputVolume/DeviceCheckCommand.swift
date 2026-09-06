import ApplicationServices
import AppKit
import Foundation

@MainActor
enum DeviceCheckCommand {
    private static var airPlayBrowser: AirPlayDeviceBrowser?
    private static var discoveredAirPlayDevices: [AirPlayDevice] = []

    static func run() {
        let store = CoreAudioDeviceStore()
        let devices = store.outputDevices()
        print("defaultOutputUID=\(store.defaultOutputUID() ?? "nil")")
        for device in devices {
            let volume = store.volume(deviceID: device.id)
                .map { String(format: "%.3f", $0) } ?? "nil"
            print([
                "name=\(device.name)",
                "uid=\(device.uid)",
                "kind=\(device.kind.rawValue)",
                "channels=\(device.outputChannels)",
                "canSetVolume=\(device.canSetVolume)",
                "canSetMute=\(device.canSetMute)",
                "volume=\(volume)",
                "defaultTarget=\(device.isDefaultTarget)",
                "members=\(device.aggregateSubDeviceUIDs.joined(separator: ","))"
            ].joined(separator: " | "))
        }
    }

    static func checkPermissions() {
        print("accessibilityTrusted=\(AXIsProcessTrusted())")
    }

    static func checkAirPlay(seconds: TimeInterval = 5) {
        let browser = AirPlayDeviceBrowser()
        airPlayBrowser = browser
        browser.onChange = { devices in
            discoveredAirPlayDevices = devices
        }
        browser.start()
        print("discoveringAirPlaySeconds=\(Int(seconds))")
        fflush(stdout)

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            browser.stop()
            if discoveredAirPlayDevices.isEmpty {
                print("airPlayDevices=none")
            } else {
                for device in discoveredAirPlayDevices {
                    print("airPlayDevice=\(device.name)")
                }
            }
            airPlayBrowser = nil
            NSApp.terminate(nil)
        }
    }

    static func showHotKeyLog() {
        let lines = HotKeyEventLogger.recentLines()
        if lines.isEmpty {
            print("no hotkey events logged")
            print("log=\(HotKeyEventLogger.logURL.path)")
            return
        }
        print("log=\(HotKeyEventLogger.logURL.path)")
        for line in lines {
            print(line)
        }
    }

    static func applyDefaultVolume() {
        let store = CoreAudioDeviceStore()
        let ddc = DDCVolumeController()
        let devices = store.outputDevices().filter(\.isDefaultTarget)
        let targetVolume: Float = 0.27
        for device in devices {
            let ok: Bool
            if device.isBenQDisplay {
                ok = ddc.setVolume(targetVolume, for: device)
            } else {
                ok = store.setVolume(targetVolume, deviceID: device.id)
            }
            print("set \(device.name) to 27% => \(ok ? "ok" : "failed")")
        }
    }

    static func activatePreferredAggregate() {
        let store = CoreAudioDeviceStore()
        guard let aggregate = store.outputDevices().first(where: \.isPreferredAggregateOutput) else {
            print("preferred aggregate not found")
            return
        }
        print("activate \(aggregate.name) => \(store.setDefaultOutput(deviceID: aggregate.id) ? "ok" : "failed")")
        print("defaultOutputUID=\(store.defaultOutputUID() ?? "nil")")
    }

    static func selectPreferredGroup() {
        activatePreferredAggregate()
        applyDefaultVolume()
    }

    static func selectOutput(matching query: String) {
        let store = CoreAudioDeviceStore()
        let devices = store.outputDevices()
        guard let device = devices.first(where: {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.uid.localizedCaseInsensitiveContains(query)
        }) else {
            print("output not found: \(query)")
            print("available:")
            for device in devices {
                print("- \(device.name) | uid=\(device.uid)")
            }
            return
        }
        let ok = store.setDefaultOutput(deviceID: device.id)
        print("select \(device.name) => \(ok ? "ok" : "failed")")
        print("defaultOutputUID=\(store.defaultOutputUID() ?? "nil")")
    }

    static func adjustVolume(delta: Float) {
        let store = CoreAudioDeviceStore()
        let ddc = DDCVolumeController()
        let targets = store.outputDevices().filter(\.isDefaultTarget)
        let current = targets.compactMap { store.volume(deviceID: $0.id) }.first ?? 0.27
        let next = min(max(current + delta, 0), 1)
        for device in targets {
            let ok: Bool
            if device.isBenQDisplay {
                ok = ddc.setVolume(next, for: device)
            } else {
                _ = store.setMuted(false, deviceID: device.id)
                ok = store.setVolume(next, deviceID: device.id)
            }
            print("set \(device.name) to \(Int((next * 100).rounded()))% => \(ok ? "ok" : "failed")")
        }
    }

    static func toggleMute() {
        let store = CoreAudioDeviceStore()
        let ddc = DDCVolumeController()
        let targets = store.outputDevices().filter(\.isDefaultTarget)
        let shouldMute = !(targets.compactMap { store.isMuted(deviceID: $0.id) }.first ?? false)
        for device in targets {
            let ok = device.isBenQDisplay
                ? ddc.setMuted(shouldMute, for: device, restoreVolume: 0.27)
                : (store.setMuted(shouldMute, deviceID: device.id)
                    || store.setVolume(shouldMute ? 0 : 0.27, deviceID: device.id))
            print("\(shouldMute ? "mute" : "unmute") \(device.name) => \(ok ? "ok" : "failed")")
        }
    }

    static func observeHotKeys(seconds: TimeInterval = 10) {
        let monitor = MediaKeyMonitor()
        var count = 0
        monitor.onRawEvent = { record in
            count += 1
            print(record.displayText)
            fflush(stdout)
        }
        monitor.onAction = { action, source in
            print("handled action=\(action.logName) source=\(source.rawValue)")
            fflush(stdout)
        }
        monitor.start()
        print("observingHotKeysSeconds=\(Int(seconds))")
        print("accessibilityTrusted=\(AXIsProcessTrusted())")
        print("eventTapCreated=\(monitor.eventTapCreated)")
        print("globalMonitorCreated=\(monitor.globalMonitorCreated)")
        print("carbonRegisteredIDs=\(monitor.carbonRegisteredIDs.sorted())")
        print("press F10/F11/F12 now...")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            print("observedRawEvents=\(count)")
            monitor.stop()
            NSApp.terminate(nil)
        }
    }

    static func doctor() {
        let store = CoreAudioDeviceStore()
        let ddc = DDCVolumeController()
        let devices = store.outputDevices()
        let defaultUID = store.defaultOutputUID()
        let benQ = devices.first(where: \.isBenQDisplay)
        let usb = devices.first {
            $0.name.localizedCaseInsensitiveContains("CX31993")
                || $0.uid.localizedCaseInsensitiveContains("CX31993")
        }
        let aggregate = devices.first(where: \.isPreferredAggregateOutput)
        let currentOutput = devices.first(where: { $0.uid == defaultUID })
        let volumeFeedback = VolumeFeedbackPlayer()
        let savedVolume = UserDefaults.standard.object(forKey: "volume") as? Float
        let verificationVolume = min(max(savedVolume ?? usb.flatMap { store.volume(deviceID: $0.id) } ?? 0.27, 0), 1)
        var failed = false

        func check(_ title: String, _ ok: Bool, detail: String = "") {
            if !ok { failed = true }
            print("\(ok ? "PASS" : "FAIL") \(title)\(detail.isEmpty ? "" : " - \(detail)")")
        }

        check("default output is recognized", currentOutput != nil, detail: currentOutput?.name ?? defaultUID ?? "nil")
        check("BenQ MA270UP detected", benQ != nil, detail: benQ?.uid ?? "missing")
        check("CX31993 detected", usb != nil, detail: usb?.uid ?? "missing")
        check("preferred aggregate detected", aggregate != nil, detail: aggregate?.uid ?? "missing")
        check("DDC backend available", ddc.isAvailable)
        check("system volume feedback sound available", volumeFeedback.isAvailable)
        check("Accessibility trusted", AXIsProcessTrusted())

        if let aggregate {
            check("activate preferred aggregate", store.setDefaultOutput(deviceID: aggregate.id), detail: store.defaultOutputUID() ?? "nil")
        }
        if let benQ {
            check("write BenQ volume via DDC", ddc.setVolume(verificationVolume, for: benQ))
        }
        if let usb {
            check("write CX31993 volume via CoreAudio", store.setVolume(verificationVolume, deviceID: usb.id))
        }

        let monitor = MediaKeyMonitor()
        monitor.start()
        check("event tap created", monitor.eventTapCreated)
        check("global monitor created", monitor.globalMonitorCreated)
        check("F10/F11/F12 Carbon registered", monitor.carbonRegisteredIDs == [10, 11, 12], detail: "\(monitor.carbonRegisteredIDs.sorted())")
        monitor.stop()

        if let currentOutput {
            check("restore original default output", store.setDefaultOutput(deviceID: currentOutput.id), detail: currentOutput.name)
            if let usb {
                check("restore CX31993 verification volume", store.setVolume(verificationVolume, deviceID: usb.id))
            }
        }

        print(failed ? "DOCTOR_RESULT=FAIL" : "DOCTOR_RESULT=PASS")
    }
}

extension CommandLine {
    static var observeHotKeySeconds: TimeInterval {
        guard let index = arguments.firstIndex(of: "--observe-hotkeys"),
              arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]) else {
            return 10
        }
        return min(max(seconds, 1), 120)
    }
}

private extension VolumeKeyAction {
    var logName: String {
        switch self {
        case .mute: "mute"
        case .decrease: "decrease"
        case .increase: "increase"
        }
    }
}
