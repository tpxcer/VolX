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
        let model = VolumeModel()
        model.refreshDevices()
        model.setUnifiedVolume(model.volume + delta, showHUD: false)
        print(model.lastStatus)
    }

    static func toggleMute() {
        let model = VolumeModel()
        model.refreshDevices()
        model.toggleMute(showHUD: false)
        print(model.lastStatus)
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
        print("press native volume media keys now (ordinary F keys are ignored)...")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            print("observedRawEvents=\(count)")
            monitor.stop()
            NSApp.terminate(nil)
        }
    }

    static func doctor() {
        // Read-only: never switch routing, probe writes or create an exclusive event tap.
        run()
        checkPermissions()
        print("DDC=disabled; Bonjour=not started; native key handling requires manual verification")
        print("DOCTOR_RESULT=READ_ONLY (not a hardware acceptance test)")
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
