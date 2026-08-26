import Foundation

struct HotKeyEventRecord: Identifiable {
    let id = UUID()
    let date: Date
    let action: VolumeKeyAction
    let source: VolumeKeySource
    let volume: Float
    let muted: Bool
    let result: String

    var displayText: String {
        let actionText: String
        switch action {
        case .mute:
            actionText = muted ? "F10 静音" : "F10 取消静音"
        case .decrease:
            actionText = "F11 减小"
        case .increase:
            actionText = "F12 增大"
        }
        let percent = Int((volume * 100).rounded())
        return "\(timeText)  \(actionText)  \(percent)%  \(source.rawValue)  \(result)"
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
