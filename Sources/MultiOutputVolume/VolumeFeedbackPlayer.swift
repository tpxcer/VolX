import AppKit
import Foundation

@MainActor
final class VolumeFeedbackPlayer {
    private static let feedbackSettingKey = "com.apple.sound.beep.feedback"
    private static let soundPaths = [
        "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
        "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/Volume.aiff"
    ]

    private let sound: NSSound?

    init() {
        let path = Self.soundPaths.first(where: FileManager.default.fileExists(atPath:))
        self.sound = path.flatMap { NSSound(contentsOfFile: $0, byReference: true) }
    }

    var isAvailable: Bool {
        sound != nil
    }

    @discardableResult
    func play() -> Bool {
        let setting = UserDefaults.standard.object(forKey: Self.feedbackSettingKey) as? NSNumber
        guard setting?.boolValue ?? true, let sound else { return false }
        if sound.isPlaying {
            sound.stop()
        }
        return sound.play()
    }
}
