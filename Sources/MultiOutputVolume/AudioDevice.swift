import CoreAudio
import Foundation

enum AudioDeviceKind: String, Codable, Hashable {
    case builtIn
    case display
    case usb
    case bluetooth
    case aggregate
    case virtual
    case unknown
}

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let manufacturer: String
    let kind: AudioDeviceKind
    let outputChannels: Int
    let canSetVolume: Bool
    let canSetMute: Bool
    var aggregateSubDeviceUIDs: [String] = []

    var isBenQDisplay: Bool {
        name.localizedCaseInsensitiveContains("BenQ")
            || manufacturer.localizedCaseInsensitiveContains("BNQ")
    }

    var isDefaultTarget: Bool {
        isBenQDisplay
            || name.localizedCaseInsensitiveContains("CX31993")
            || uid.localizedCaseInsensitiveContains("CX31993")
    }

    var isPreferredAggregateOutput: Bool {
        kind == .aggregate && name.localizedCaseInsensitiveContains("显示器+音箱")
    }

    var symbolName: String {
        switch kind {
        case .display: "display"
        case .usb: "speaker.wave.2.fill"
        case .bluetooth: "airplayaudio"
        case .aggregate: "speaker.wave.2.circle"
        case .builtIn: "macmini"
        case .virtual: "circle.dashed"
        case .unknown: "speaker.wave.2"
        }
    }
}
