import Foundation

enum VolumeKeyAction: Equatable, Sendable {
    case mute, decrease, increase
}
struct NativeVolumeKey {
    let action: VolumeKeyAction?
    static func decode(type: UInt32, subtype: Int, data: Int, modifiers: UInt64) -> NativeVolumeKey? {
        // CG systemDefined=14, NX_SUBTYPE_AUX_CONTROL_BUTTONS=8.
        // Preserve Shift/Control/Option/Command combinations for macOS.
        let modified: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
        guard type == 14, subtype == 8, modifiers & modified == 0 else { return nil }
        let code = (data >> 16) & 0xffff
        let state = (data >> 8) & 0xff
        guard state == 0x0a || state == 0x0b else { return nil }
        let action: VolumeKeyAction
        switch code {
        case 0: action = .increase // NX_KEYTYPE_SOUND_UP
        case 1: action = .decrease // NX_KEYTYPE_SOUND_DOWN
        case 7: action = .mute
        default: return nil
        }
        let repeatingMute = action == .mute && data & 1 != 0
        return NativeVolumeKey(action: state == 0x0a && !repeatingMute ? action : nil)
    }
}
struct OutputSwitchResult {
    let output: Bool
    let system: Bool
    var complete: Bool { output && system }
}

enum VerifiedLevelIO {
    static func read(elements: [Int], get: (Int) -> Float?) -> Float? {
        let values = elements.compactMap(get)
        guard !elements.isEmpty, values.count == elements.count,
              values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { return nil }
        return values.max()
    }
    static func write(_ value: Float, elements: [Int], set: (Int, Float) -> Bool,
                      get: (Int) -> Float?) -> Bool {
        guard value.isFinite, !elements.isEmpty else { return false }
        let target = min(max(value, 0), 1)
        // map, not allSatisfy: attempt and inspect every channel, without short-circuit.
        let results = elements.map { element in
            let wrote = set(element, target)
            let actual = get(element)
            return wrote && (actual.map { $0.isFinite && abs($0 - target) <= 0.005 } ?? false)
        }
        return results.allSatisfy { $0 }
    }
}

struct DeviceLevel {
    let uid: String
    let volume: Float?
    let muted: Bool?
    var confirmedSilent: Bool { muted == true || volume == 0 }
}

struct DeviceTarget {
    let uid: String
    let volume: Float
    let muted: Bool
}

struct DeviceWriteOutcome {
    let uid: String
    let confirmed: Bool
    let actual: DeviceLevel
}

final class SafeVolumeController {
    private(set) var restoreLevels: [String: Float] = [:]
    init(restoreLevels: [String: Float] = [:]) {
        self.restoreLevels = restoreLevels.filter { $0.value.isFinite && $0.value > 0 && $0.value <= 1 }
    }
    func muteTargets(_ states: [DeviceLevel], muted: Bool) -> [DeviceTarget] {
        states.map { state in
            // Repeated/partially failed mute must not replace a saved audible level with zero.
            if muted, let level = state.volume, level.isFinite, level > 0 {
                restoreLevels[state.uid] = level
            }
            return DeviceTarget(uid: state.uid,
                volume: muted ? 0 : ((state.volume.flatMap { $0.isFinite && $0 > 0 && $0 <= 1 ? $0 : nil }) ?? restoreLevels[state.uid] ?? 0),
                muted: muted)
        }
    }
    func apply(_ targets: [DeviceTarget], write: (DeviceTarget) -> Bool,
               read: (String) -> DeviceLevel) -> [DeviceWriteOutcome] {
        let outcomes = targets.map { target in
            let wrote = write(target)
            let actual = read(target.uid)
            let levelMatches = actual.volume.map { $0.isFinite && abs($0 - target.volume) <= 0.005 } ?? false
            // No mute property is OK only when volume readback proves silence (mute),
            // or the backend has established there is no hardware mute (unmute).
            let muteMatches = target.muted ? actual.confirmedSilent : actual.muted == false
            return DeviceWriteOutcome(uid: target.uid,
                confirmed: wrote && levelMatches && muteMatches, actual: actual)
        }
        observe(outcomes.map(\.actual))
        return outcomes
    }
    private(set) var volume: Float = 0
    private(set) var isMuted = false
    func observe(_ states: [DeviceLevel]) {
        volume = states.compactMap(\.volume).filter { $0.isFinite }.max() ?? 0
        isMuted = !states.isEmpty && states.allSatisfy(\.confirmedSilent)
    }
}
