import Foundation

enum HotKeyEventLogger {
    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MultiOutputVolume/hotkeys.log")
    }

    static func append(_ record: HotKeyEventRecord) {
        let line = "\(Self.timestamp(record.date)) action=\(record.action.logName) source=\(record.source.rawValue) volume=\(Int((record.volume * 100).rounded())) muted=\(record.muted) result=\(record.result)\n"
        do {
            let folder = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                try line.write(to: logURL, atomically: true, encoding: .utf8)
            }
            trimIfNeeded()
        } catch {
            // Logging must never interrupt volume control.
        }
    }

    static func recentLines(limit: Int = 20) -> [String] {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n").suffix(limit).map(String.init)
    }

    private static func trimIfNeeded() {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n")
        guard lines.count > 200 else { return }
        let trimmed = lines.suffix(200).joined(separator: "\n") + "\n"
        try? trimmed.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
