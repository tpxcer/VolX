import CoreAudio
import Foundation

protocol AudioDeviceStoring {
    func outputDevices() -> [AudioDevice]
    func defaultOutputUID() -> String?
    func setDefaultOutput(deviceID: AudioDeviceID) -> Bool
    func volume(deviceID: AudioDeviceID) -> Float?
    func isMuted(deviceID: AudioDeviceID) -> Bool?
    func setVolume(_ volume: Float, deviceID: AudioDeviceID) -> Bool
    func setMuted(_ muted: Bool, deviceID: AudioDeviceID) -> Bool
}

final class CoreAudioDeviceStore: AudioDeviceStoring {
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
        var actualOutput: UInt32 = 0
        var actualSystem: UInt32 = 0
        let outputRead = getUInt32Property(kAudioHardwarePropertyDefaultOutputDevice,
            deviceID: AudioObjectID(kAudioObjectSystemObject), scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain, value: &actualOutput)
        let systemRead = getUInt32Property(kAudioHardwarePropertyDefaultSystemOutputDevice,
            deviceID: AudioObjectID(kAudioObjectSystemObject), scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain, value: &actualSystem)
        return OutputSwitchResult(output: outputOK && outputRead && actualOutput == deviceID,
            system: systemOK && systemRead && actualSystem == deviceID).complete
    }

    private func volumeElements(deviceID: AudioDeviceID) -> [Int] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(deviceID, &address) { return [0] }
        let count = channelCount(deviceID: deviceID)
        return count > 0 ? Array(1...count) : []
    }

    func volume(deviceID: AudioDeviceID) -> Float? {
        VerifiedLevelIO.read(elements: volumeElements(deviceID: deviceID)) { element in
            scalarProperty(kAudioDevicePropertyVolumeScalar, deviceID: deviceID,
                scope: kAudioDevicePropertyScopeOutput, element: UInt32(element))
        }
    }

    func setVolume(_ volume: Float, deviceID: AudioDeviceID) -> Bool {
        VerifiedLevelIO.write(volume, elements: volumeElements(deviceID: deviceID), set: { element, value in
            self.setScalarProperty(kAudioDevicePropertyVolumeScalar, value: value, deviceID: deviceID,
                scope: kAudioDevicePropertyScopeOutput, element: UInt32(element))
        }, get: { element in
            self.scalarProperty(kAudioDevicePropertyVolumeScalar, deviceID: deviceID,
                scope: kAudioDevicePropertyScopeOutput, element: UInt32(element))
        })
    }

    func isMuted(deviceID: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if !AudioObjectHasProperty(deviceID, &address) {
            // A per-channel mute property is not safely represented by one Bool.
            for element in 1...max(channelCount(deviceID: deviceID), 1) {
                address.mElement = UInt32(element)
                if AudioObjectHasProperty(deviceID, &address) { return nil }
            }
            // Only a real, readable device with no mute property is known unmuted.
            return volume(deviceID: deviceID) == nil ? nil : false
        }
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
        let wrote = setUInt32Property(
            kAudioDevicePropertyMute,
            deviceID: deviceID,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain,
            value: &value
        )
        return wrote && isMuted(deviceID: deviceID) == muted
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
        var transport: UInt32 = 0
        _ = getUInt32Property(kAudioDevicePropertyTransportType, deviceID: deviceID,
                             scope: kAudioObjectPropertyScopeGlobal,
                             element: kAudioObjectPropertyElementMain, value: &transport)
        let kind: AudioDeviceKind = transport == kAudioDeviceTransportTypeAggregate
            ? .aggregate : classify(name: name, uid: uid, manufacturer: manufacturer)
        return AudioDevice(
            id: deviceID,
            uid: uid,
            name: name,
            manufacturer: manufacturer,
            kind: kind,
            outputChannels: outputChannels,
            canSetVolume: canSetVolume(deviceID: deviceID),
            canSetMute: canSetMute(deviceID: deviceID),
            aggregateSubDeviceUIDs: kind == .aggregate ? aggregateMembers(deviceID: deviceID) : []
        )
    }

    private func aggregateMembers(deviceID: AudioDeviceID) -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyFullSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFArray>?
        var size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr,
              let members = value?.takeRetainedValue() as? [String] else { return [] }
        return members
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
