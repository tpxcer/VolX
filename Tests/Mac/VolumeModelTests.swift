import XCTest
@testable import MultiOutputVolume

final class FakeAudioStore: AudioDeviceStoring {
    var output = "pair"
    var writes = 0
    var omitB = false
    var failUID: String?
    var levels: [String: Float] = ["a": 0.2, "b": 0.7]
    var mutes: [String: Bool] = ["a": true, "b": false]
    let a = AudioDevice(id: 1, uid: "a", name: "Speaker", manufacturer: "Apple", kind: .builtIn, outputChannels: 2, canSetVolume: true, canSetMute: true)
    let b = AudioDevice(id: 2, uid: "b", name: "Headphones", manufacturer: "Apple", kind: .builtIn, outputChannels: 2, canSetVolume: true, canSetMute: true)
    func outputDevices() -> [AudioDevice] {
        [a, b, AudioDevice(id: 3, uid: "pair", name: "Pair", manufacturer: "Apple", kind: .aggregate, outputChannels: 2, canSetVolume: false, canSetMute: false, aggregateSubDeviceUIDs: ["a", "b"])].filter { !omitB || $0.uid != "b" }
    }
    func uid(_ id: UInt32) -> String { id == 1 ? "a" : "b" }
    func defaultOutputUID() -> String? { output }
    func setDefaultOutput(deviceID: UInt32) -> Bool { output = uid(deviceID); return false }
    func volume(deviceID: UInt32) -> Float? { levels[uid(deviceID)] }
    func isMuted(deviceID: UInt32) -> Bool? { mutes[uid(deviceID)] }
    func setVolume(_ volume: Float, deviceID: UInt32) -> Bool {
        writes += 1
        let key = uid(deviceID)
        if key == failUID { return false }
        levels[key] = volume
        return true
    }
    func setMuted(_ muted: Bool, deviceID: UInt32) -> Bool {
        writes += 1
        let key = uid(deviceID)
        if key == failUID { return false }
        mutes[key] = muted
        return true
    }
}

final class VolumeModelTests: XCTestCase {
    @MainActor func testStartupAndSwitchAreReadOnly() {
        let store = FakeAudioStore()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(Float(1), forKey: "volume")
        defaults.set(true, forKey: "isMuted")
        let model = VolumeModel(defaults: defaults, store: store)
        model.start(enableHotKeys: false)
        defer { model.stop() }
        XCTAssertEqual(store.writes, 0)
        XCTAssertEqual(model.volume, 0.7)
        XCTAssertFalse(model.isMuted)
        store.output = "a"
        model.refreshDevices()
        XCTAssertEqual(store.writes, 0)
        XCTAssertEqual(model.volume, 0.2)
        XCTAssertTrue(model.isMuted)
        model.selectOnly("b")
        XCTAssertEqual(store.writes, 0)
        XCTAssertEqual(model.activeOutputUID, "b")
        XCTAssertTrue(model.lastStatus.contains("未全部成功"))
    }

    @MainActor func testMissingDeclaredAggregateMemberRemainsUnconfirmed() {
        let store = FakeAudioStore()
        store.omitB = true
        store.levels["a"] = 0
        let model = VolumeModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, store: store)
        model.refreshDevices()
        XCTAssertEqual(model.selectedDeviceUIDs, ["a", "b"])
        XCTAssertFalse(model.isMuted)
        model.toggleMute(showHUD: false)
        XCTAssertFalse(model.isMuted)
        XCTAssertTrue(model.lastStatus.contains("未确认：b"))
        model.refreshDevices()
        XCTAssertEqual(model.selectedDeviceUIDs, ["a", "b"])
        XCTAssertFalse(model.isMuted)
        model.setUnifiedVolume(0, showHUD: false)
        XCTAssertFalse(model.isMuted)
        XCTAssertTrue(model.lastStatus.contains("未确认：b"))
    }

    @MainActor func testPartialMuteAndRestore() {
        let store = FakeAudioStore()
        store.mutes = ["a": false, "b": false]
        let model = VolumeModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, store: store)
        model.refreshDevices()
        store.failUID = "b"
        model.toggleMute(showHUD: false)
        XCTAssertFalse(model.isMuted)
        XCTAssertTrue(model.lastStatus.contains("Headphones"))
        XCTAssertTrue(model.lastStatus.contains("未确认"))
        store.failUID = nil
        model.toggleMute(showHUD: false) // retry mute, preserving original per-device levels
        XCTAssertTrue(model.isMuted)
        model.toggleMute(showHUD: false)
        XCTAssertFalse(model.isMuted)
        XCTAssertEqual(store.levels["a"], 0.2)
        XCTAssertEqual(store.levels["b"], 0.7)
    }

    @MainActor func testPairBalanceSurvivesSwitchWithoutWriting() {
        let store = FakeAudioStore()
        let model = VolumeModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, store: store)
        model.refreshDevices()
        model.setOutputBalance(0.5)
        model.setUnifiedVolume(0.4, showHUD: false)
        XCTAssertEqual(store.levels["a"], 0.2)
        XCTAssertEqual(store.levels["b"], 0.4)
        let writes = store.writes
        store.output = "a"
        model.refreshDevices()
        store.output = "pair"
        model.refreshDevices()
        XCTAssertEqual(model.outputBalance, 0.5)
        XCTAssertEqual(store.writes, writes)
    }

    @MainActor func testMuteRestoreSurvivesRelaunchWithoutStartupWrites() {
        let store = FakeAudioStore()
        store.mutes = ["a": false, "b": false]
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = VolumeModel(defaults: defaults, store: store)
        first.refreshDevices()
        first.toggleMute(showHUD: false)
        let writes = store.writes
        let second = VolumeModel(defaults: defaults, store: store)
        second.refreshDevices()
        XCTAssertEqual(store.writes, writes)
        XCTAssertTrue(second.isMuted)
        second.toggleMute(showHUD: false)
        XCTAssertEqual(store.levels["a"], 0.2)
        XCTAssertEqual(store.levels["b"], 0.7)
    }

    func testDDCExplicitlyDisabled() {
        XCTAssertFalse(DDCVolumeController().isAvailable)
        let display = AudioDevice(id: 4, uid: "display", name: "BenQ", manufacturer: "BNQ", kind: .display, outputChannels: 2, canSetVolume: false, canSetMute: false)
        XCTAssertFalse(DDCVolumeController().setVolume(0.5, for: display))
    }
}
