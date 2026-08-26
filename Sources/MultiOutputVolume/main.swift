import AppKit

let app = NSApplication.shared
if CommandLine.arguments.contains("--observe-hotkeys") {
    app.setActivationPolicy(.accessory)
    DeviceCheckCommand.observeHotKeys(seconds: CommandLine.observeHotKeySeconds)
    app.run()
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
delegate.bootstrap()
app.run()
