import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = VolumeModel()
    private var statusController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
    }

    func bootstrap() {
        if CommandLine.arguments.contains("--check-devices") {
            DeviceCheckCommand.run()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--doctor") {
            DeviceCheckCommand.doctor()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--apply-default-volume") {
            DeviceCheckCommand.applyDefaultVolume()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--activate-aggregate") {
            DeviceCheckCommand.activatePreferredAggregate()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--select-preferred-group") {
            DeviceCheckCommand.selectPreferredGroup()
            NSApp.terminate(nil)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--select-output"),
           CommandLine.arguments.indices.contains(index + 1) {
            DeviceCheckCommand.selectOutput(matching: CommandLine.arguments[index + 1])
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--volume-up") {
            DeviceCheckCommand.adjustVolume(delta: 0.0625)
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--volume-down") {
            DeviceCheckCommand.adjustVolume(delta: -0.0625)
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--toggle-mute") {
            DeviceCheckCommand.toggleMute()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--check-permissions") {
            DeviceCheckCommand.checkPermissions()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--check-airplay") {
            DeviceCheckCommand.checkAirPlay()
            return
        }
        if CommandLine.arguments.contains("--hotkey-log") {
            DeviceCheckCommand.showHotKeyLog()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--check-interface") {
            let passed = InterfaceCheckCommand.run()
            if passed {
                NSApp.terminate(nil)
                return
            }
            exit(1)
        }
        statusController = StatusBarController(model: model)
        if CommandLine.arguments.contains("--preview-slider-drag") {
            model.isVolumeSliderDragging = true
        }
        model.start(enableHotKeys: !CommandLine.arguments.contains("--no-hotkeys"))
        if CommandLine.arguments.contains("--self-test-hotkeys") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [model] in
                model.runHotKeySelfTest()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                DeviceCheckCommand.showHotKeyLog()
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--check-hotkeys") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [model] in
                print(model.hotKeyDiagnostics())
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--show-hud") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [model] in
                model.showHUDForCurrentVolume()
            }
        }
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [statusController] in
                statusController?.showPanelForTesting()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
