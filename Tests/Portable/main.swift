import Foundation

var failures = 0
func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() { print("PASS \(name)") }
    else { failures += 1; print("FAIL \(name)") }
}

// Compile this against the actual application core, not a reimplementation.
let states = [DeviceLevel(uid: "a", volume: 0.2, muted: true),
              DeviceLevel(uid: "b", volume: 0.7, muted: false)]
let controller = SafeVolumeController()
controller.observe(states)
check("observation adopts actual maximum level", controller.volume == 0.7)
check("mixed hardware mute never confirms group mute", !controller.isMuted)
controller.observe([DeviceLevel(uid: "c", volume: 0.4, muted: true)])
check("output change adopts muted hardware", controller.isMuted && controller.volume == 0.4)
controller.observe([DeviceLevel(uid: "c", volume: nil, muted: nil)])
check("unknown hardware never confirms muted", !controller.isMuted)

var hardware = ["a": DeviceLevel(uid: "a", volume: 0.2, muted: false),
                "b": DeviceLevel(uid: "b", volume: 0.7, muted: false)]
let beforeMute = Array(hardware.values)
let muteTargets = controller.muteTargets(beforeMute, muted: true)
check("mute targets silence every member", muteTargets.count == 2 && muteTargets.allSatisfy { $0.volume == 0 && $0.muted })
let outcomes = controller.apply(muteTargets, write: { target in
    if target.uid == "b" { return false }
    hardware[target.uid] = DeviceLevel(uid: target.uid, volume: target.volume, muted: target.muted)
    return true
}, read: { hardware[$0]! })
check("partial mute reports one failure", outcomes.filter { !$0.confirmed }.map(\.uid) == ["b"])
check("partial mute never confirms group mute", !controller.isMuted)
let restore = controller.muteTargets(Array(hardware.values), muted: false)
check("unmute restores each device independently", restore.first { $0.uid == "a" }?.volume == 0.2 && restore.first { $0.uid == "b" }?.volume == 0.7)
let falseSuccess = controller.apply([DeviceTarget(uid: "b", volume: 0, muted: true)], write: { _ in true }, read: { hardware[$0]! })
check("successful API without readback is not success", falseSuccess.allSatisfy { !$0.confirmed })
let failedWrite = controller.apply([DeviceTarget(uid: "a", volume: 0, muted: true)], write: { _ in false }, read: { hardware[$0]! })
check("failed API is reported even when silent", failedWrite.allSatisfy { !$0.confirmed })
check("empty devices never confirms mute", { controller.observe([]); return !controller.isMuted }())
check("NX up down is intercepted", NativeVolumeKey.decode(type: 14, subtype: 8, data: (0 << 16) | 0x0A00, modifiers: 0)?.action == .increase)
check("NX down release is swallowed without action", NativeVolumeKey.decode(type: 14, subtype: 8, data: (1 << 16) | 0x0B00, modifiers: 0)?.action == nil && NativeVolumeKey.decode(type: 14, subtype: 8, data: (1 << 16) | 0x0B00, modifiers: 0) != nil)
check("NX mute repeat does not toggle repeatedly", NativeVolumeKey.decode(type: 14, subtype: 8, data: (7 << 16) | 0x0A01, modifiers: 0)?.action == nil)
for key in [0, 109, 103, 111] {
    check("ordinary key passes through \(key)", NativeVolumeKey.decode(type: 10, subtype: 8, data: key, modifiers: 0) == nil)
    check("modified F key passes through \(key)", NativeVolumeKey.decode(type: 10, subtype: 8, data: key, modifiers: 1 << 20) == nil)
}
check("modified NX passes to system", NativeVolumeKey.decode(type: 14, subtype: 8, data: 0x0A00, modifiers: 1 << 19) == nil)
check("other media key untouched", NativeVolumeKey.decode(type: 14, subtype: 8, data: (16 << 16) | 0x0A00, modifiers: 0) == nil)
check("other system subtype untouched", NativeVolumeKey.decode(type: 14, subtype: 9, data: 0x0A00, modifiers: 0) == nil)
check("partial output switch is not total success", !OutputSwitchResult(output: true, system: false).complete)
check("complete output switch is success", OutputSwitchResult(output: true, system: true).complete)
var channels: [Int: Float] = [1: 0.2, 2: 0.7]
var channelWrites: [Int] = []
let partialChannel = VerifiedLevelIO.write(0.5, elements: [1, 2], set: { channel, value in
    channelWrites.append(channel)
    if channel == 2 { return false }
    channels[channel] = value
    return true
}, get: { channels[$0] })
check("stereo partial write is failure", !partialChannel)
check("all channels are attempted", channelWrites == [1, 2])
check("missing channel read is unknown", VerifiedLevelIO.read(elements: [1, 2], get: { $0 == 1 ? 0 : nil }) == nil)
check("read uses loudest channel not false zero", VerifiedLevelIO.read(elements: [1, 2], get: { channels[$0] }) == 0.7)
check("readback mismatch fails", !VerifiedLevelIO.write(0.3, elements: [1], set: { _, _ in true }, get: { _ in 0.8 }))
check("readback matching succeeds", VerifiedLevelIO.write(0.3, elements: [1], set: { _, _ in true }, get: { _ in 0.3 }))
let relaunched = SafeVolumeController(restoreLevels: controller.restoreLevels)
check("relaunch restores muted device's saved level only on request", relaunched.muteTargets([DeviceLevel(uid: "a", volume: 0, muted: true)], muted: false).first?.volume == 0.2)
check("external positive level takes precedence over stale restore", relaunched.muteTargets([DeviceLevel(uid: "a", volume: 0.8, muted: true)], muted: false).first?.volume == 0.8)
// Aggregate membership must not be intersected with transient enumeration.
let memberA = AudioDevice(id: 1, uid: "a", name: "Speaker", manufacturer: "Apple", kind: .builtIn, outputChannels: 2, canSetVolume: true, canSetMute: true)
let pair = AudioDevice(id: 3, uid: "pair", name: "Pair", manufacturer: "Apple", kind: .aggregate, outputChannels: 2, canSetVolume: false, canSetMute: false, aggregateSubDeviceUIDs: ["a", "b"])
let expected = AudioDevice.selectionForSystemOutput(uid: "pair", devices: [pair, memberA])!
check("aggregate retains missing declared member", expected == ["a", "b"])
let missingController = SafeVolumeController()
let missingStates = expected.sorted().map { DeviceLevel(uid: $0, volume: $0 == "a" ? 0 : nil, muted: $0 == "a" ? true : nil) }
missingController.observe(missingStates)
check("missing aggregate member prevents observed mute", !missingController.isMuted)
let missingOutcomes = missingController.apply(missingController.muteTargets(missingStates, muted: true), write: { $0.uid == "a" }, read: { uid in missingStates.first { $0.uid == uid }! })
check("missing aggregate member is an unconfirmed outcome", missingOutcomes.filter { !$0.confirmed }.map(\.uid) == ["b"])
check("missing aggregate member prevents applied mute", !missingController.isMuted)
if failures > 0 { exit(1) }
