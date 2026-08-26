import CoreAudio
import Foundation

final class CoreAudioDeviceStore {
    func outputDevices() -> [AudioDevice] {
        allDeviceIDs().compactMap(device(for:)).filter { $0.outputChannels > 0 }
            .sorted { lhs, rhs in
                if lhs.isDefaultTarget != rhs.isDefaultTarget {
                    return lhs.isDefaultTarget && !rhs.isDefaultTarget
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func defaultOutputUID() -> String? {
        var deviceID = AudioDeviceID(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return nil
        }
        return stringProperty(kAudioDevicePropertyDeviceUID, deviceID: deviceID)
    }

    func setDefaultOutput(deviceID: AudioDeviceID) -> Bool {
        var output = deviceID
        var systemOutput = deviceID
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var systemAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let outputOK = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &outputAddress,
            0,
            nil,
            size,
            &output
        ) == noErr
        let systemOK = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &systemAddress,
            0,
            nil,
            size,
            &systemOutput
        ) == noErr
        return outputOK || systemOK
    }

    func volume(deviceID: AudioDeviceID) -> Float? {
        if let master = scalarProperty(
            kAudioDevicePropertyVolumeScalar,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            return master
        }
        let left = scalarProperty(
            kAudioDevicePropertyVolumeScalar,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: 1
        )
        let right = scalarProperty(
            kAudioDevicePropertyVolumeScalar,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: 2
        )
        switch (left, right) {
        case let (.some(left), .some(right)):
            return (left + right) / 2
        case let (.some(value), nil), let (nil, .some(value)):
            return value
        default:
            return nil
        }
    }

    func setVolume(_ volume: Float, deviceID: AudioDeviceID) -> Bool {
        let clamped = min(max(volume, 0), 1)
        var changed = false
        if setScalarProperty(
            kAudioDevicePropertyVolumeScalar,
            value: clamped,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        ) {
            changed = true
        }
        if setScalarProperty(
            kAudioDevicePropertyVolumeScalar,
            value: clamped,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: 1
        ) {
            changed = true
        }
        if setScalarProperty(
            kAudioDevicePropertyVolumeScalar,
            value: clamped,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: 2
        ) {
            changed = true
        }
        return changed
    }

    func isMuted(deviceID: AudioDeviceID) -> Bool? {
        var value: UInt32 = 0
        guard getUInt32Property(
            kAudioDevicePropertyMute,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain,
            value: &value
        ) else {
            return nil
        }
        return value != 0
    }

    func setMuted(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
        var value: UInt32 = muted ? 1 : 0
        return setUInt32Property(
            kAudioDevicePropertyMute,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain,
            value: &value
        )
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else {
            return []
        }
        return devices
    }

    private func device(for deviceID: AudioDeviceID) -> AudioDevice? {
        guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, deviceID: deviceID),
              let name = stringProperty(kAudioObjectPropertyName, deviceID: deviceID) else {
            return nil
        }
        let manufacturer = stringProperty(kAudioObjectPropertyManufacturer, deviceID: deviceID) ?? ""
        let outputChannels = channelCount(deviceID: deviceID)
        let kind = classify(name: name, uid: uid, manufacturer: manufacturer)
        return AudioDevice(
            id: deviceID,
            uid: uid,
            name: name,
            manufacturer: manufacturer,
            kind: kind,
            outputChannels: outputChannels,
            canSetVolume: canSetVolume(deviceID: deviceID),
            canSetMute: canSetMute(deviceID: deviceID)
        )
    }

    private func classify(name: String, uid: String, manufacturer: String) -> AudioDeviceKind {
        let haystack = "\(name) \(uid) \(manufacturer)"
        if uid.hasPrefix("~:AMS") { return .aggregate }
        if haystack.localizedCaseInsensitiveContains("BenQ")
            || haystack.localizedCaseInsensitiveContains("BNQ")
            || haystack.localizedCaseInsensitiveContains("DisplayPort") {
            return .display
        }
        if haystack.localizedCaseInsensitiveContains("CX31993")
            || haystack.localizedCaseInsensitiveContains("USB")
            || haystack.localizedCaseInsensitiveContains("TTGK") {
            return .usb
        }
        if haystack.localizedCaseInsensitiveContains("BuiltIn")
            || name.localizedCaseInsensitiveContains("Mac mini") {
            return .builtIn
        }
        if uid.contains(":output") && uid.contains("-") { return .bluetooth }
        if haystack.localizedCaseInsensitiveContains("virtual")
            || haystack.localizedCaseInsensitiveContains("ARK")
            || haystack.localizedCaseInsensitiveContains("Oray") {
            return .virtual
        }
        return .unknown
    }

    private func channelCount(deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else {
            return 0
        }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer) == noErr else {
            return 0
        }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func canSetVolume(deviceID: AudioDeviceID) -> Bool {
        isSettable(
            kAudioDevicePropertyVolumeScalar,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        || isSettable(
            kAudioDevicePropertyVolumeScalar,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: 1
        )
        || isSettable(
            kAudioDevicePropertyVolumeScalar,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: 2
        )
    }

    private func canSetMute(deviceID: AudioDeviceID) -> Bool {
        isSettable(
            kAudioDevicePropertyMute,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String
    }

    private func scalarProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float? {
        var value: Float32 = 0
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private func setScalarProperty(
        _ selector: AudioObjectPropertySelector,
        value: Float,
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var scalar = Float32(value)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
              settable.boolValue else {
            return false
        }
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &scalar) == noErr
    }

    private func getUInt32Property(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        value: inout UInt32
    ) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectHasProperty(deviceID, &address)
            && AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
    }

    private func setUInt32Property(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        value: inout UInt32
    ) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
              settable.boolValue else {
            return false
        }
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }

    private func isSettable(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var settable = DarwinBoolean(false)
        return AudioObjectHasProperty(deviceID, &address)
            && AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr
            && settable.boolValue
    }
}
