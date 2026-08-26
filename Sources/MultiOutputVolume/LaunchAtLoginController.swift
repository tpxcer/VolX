import Foundation

enum LaunchAtLoginController {
    private static let label = "com.tpxcer.MultiOutputVolume"

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try installLaunchAgent()
        } else {
            try removeLaunchAgent()
        }
    }

    private static func installLaunchAgent() throws {
        let executablePath = Bundle.main.executablePath
            ?? "/Applications/VolX.app/Contents/MacOS/MultiOutputVolume"
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let folder = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: launchAgentURL, options: .atomic)
    }

    private static func removeLaunchAgent() throws {
        guard FileManager.default.fileExists(atPath: launchAgentURL.path) else { return }
        try FileManager.default.removeItem(at: launchAgentURL)
    }
}
