@preconcurrency import AppKit
import Carbon
import IOKit.hidsystem

private let systemDefinedEventType = CGEventType(rawValue: 14)!

enum VolumeKeyAction {
    case mute
    case decrease
    case increase
}

enum VolumeKeySource: String {
    case eventTap
    case globalMonitor
    case carbon
    case selfTest
}

struct RawHotKeyEventRecord {
    let source: VolumeKeySource
    let eventType: String
    let keyCode: Int?
    let data1: Int?
    let keyState: Int?
    let action: VolumeKeyAction?

    var displayText: String {
        let keyCodeText = keyCode.map(String.init) ?? "nil"
        let dataText = data1.map(String.init) ?? "nil"
        let stateText = keyState.map(String.init) ?? "nil"
        let actionText: String
        switch action {
        case .mute:
            actionText = "mute"
        case .decrease:
            actionText = "decrease"
        case .increase:
            actionText = "increase"
        case nil:
            actionText = "nil"
        }
        return "source=\(source.rawValue) type=\(eventType) keyCode=\(keyCodeText) data1=\(dataText) keyState=\(stateText) action=\(actionText)"
    }
}

final class MediaKeyMonitor: @unchecked Sendable {
    var onAction: (@MainActor (VolumeKeyAction, VolumeKeySource) -> Void)?
    var onRawEvent: (@MainActor (RawHotKeyEventRecord) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapRetryTimer: Timer?
    private var globalEventMonitor: Any?
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private(set) var eventTapCreated = false
    var eventTapReceivedEvent = false
    private(set) var accessibilityTrusted = false
    private(set) var globalMonitorCreated = false
    private(set) var globalMonitorReceivedEvent = false
    private(set) var carbonRegisteredIDs: Set<UInt32> = []
    private(set) var lastSource: VolumeKeySource?
    private var lastEmittedAction: VolumeKeyAction?
    private var lastEmitTime: CFAbsoluteTime = 0
    private let signature: OSType = 0x4D4F5656 // MOVV

    func start() {
        eventTapCreated = false
        eventTapReceivedEvent = false
        globalMonitorCreated = false
        globalMonitorReceivedEvent = false
        carbonRegisteredIDs = []
        lastSource = nil
        lastEmittedAction = nil
        lastEmitTime = 0
        accessibilityTrusted = AXIsProcessTrusted()
        if !accessibilityTrusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        startEventTap()
        if !eventTapCreated {
            startEventTapRetry()
        }
        startGlobalMonitorFallback()
        startCarbonFallback()
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        eventTapRetryTimer?.invalidate()
        eventTapRetryTimer = nil
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        globalEventMonitor = nil
        globalMonitorCreated = false
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        carbonRegisteredIDs.removeAll()
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
        hotKeyHandler = nil
    }

    private func startEventTap() {
        guard eventTap == nil else { return }
        accessibilityTrusted = AXIsProcessTrusted()
        guard accessibilityTrusted else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << systemDefinedEventType.rawValue)
        let ref = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: mediaKeyEventCallback,
            userInfo: ref
        ) else {
            return
        }
        eventTap = tap
        eventTapCreated = true
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func startEventTapRetry() {
        guard eventTapRetryTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.startEventTap()
            if self.eventTapCreated {
                timer.invalidate()
                self.eventTapRetryTimer = nil
            }
        }
        eventTapRetryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startGlobalMonitorFallback() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.systemDefined, .keyDown]) { [weak self] event in
            self?.handleGlobalEvent(event)
        }
        globalMonitorCreated = globalEventMonitor != nil
    }

    private func startCarbonFallback() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )
        guard status == noErr else { return }

        registerCarbonHotKey(keyCode: UInt32(kVK_F10), id: 10)
        registerCarbonHotKey(keyCode: UInt32(kVK_F11), id: 11)
        registerCarbonHotKey(keyCode: UInt32(kVK_F12), id: 12)
    }

    private func registerCarbonHotKey(keyCode: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
            carbonRegisteredIDs.insert(id)
        }
    }

    fileprivate func handleCarbonHotKey(id: UInt32) {
        let action: VolumeKeyAction?
        switch id {
        case 10: action = .mute
        case 11: action = .decrease
        case 12: action = .increase
        default: action = nil
        }
        if let action {
            emit(action, source: .carbon)
        }
    }

    fileprivate func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown || type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard let action = functionKeyAction(for: Int(keyCode)) else {
                return Unmanaged.passUnretained(event)
            }
            let eventType = type == .keyDown ? "keyDown" : "keyUp"
            emitRaw(source: .eventTap, eventType: eventType, keyCode: Int(keyCode), data1: nil, keyState: nil, action: type == .keyDown ? action : nil)
            if type == .keyDown {
                emit(action, source: .eventTap)
            }
            return nil
        }

        guard type == systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF0000) >> 16
        let keyFlags = data & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        guard let action = mediaKeyAction(for: Int32(keyCode)) else {
            emitRaw(source: .eventTap, eventType: "systemDefined", keyCode: keyCode, data1: data, keyState: keyState, action: nil)
            return Unmanaged.passUnretained(event)
        }
        emitRaw(
            source: .eventTap,
            eventType: "systemDefined",
            keyCode: keyCode,
            data1: data,
            keyState: keyState,
            action: keyState == 0x0A ? action : nil
        )
        if keyState == 0x0A {
            emit(action, source: .eventTap)
        }
        return keyState == 0x0A || keyState == 0x0B
            ? nil
            : Unmanaged.passUnretained(event)
    }

    private func functionKeyAction(for keyCode: Int) -> VolumeKeyAction? {
        switch keyCode {
        case kVK_F10: .mute
        case kVK_F11: .decrease
        case kVK_F12: .increase
        default: nil
        }
    }

    private func mediaKeyAction(for keyCode: Int32) -> VolumeKeyAction? {
        switch keyCode {
        case NX_KEYTYPE_MUTE: .mute
        case NX_KEYTYPE_SOUND_DOWN: .decrease
        case NX_KEYTYPE_SOUND_UP: .increase
        default: nil
        }
    }

    private func handleGlobalEvent(_ event: NSEvent) {
        globalMonitorReceivedEvent = true
        if event.type == .keyDown {
            switch Int(event.keyCode) {
            case kVK_F10:
                emitRaw(source: .globalMonitor, eventType: "keyDown", keyCode: Int(event.keyCode), data1: nil, keyState: nil, action: .mute)
                emit(.mute, source: .globalMonitor)
            case kVK_F11:
                emitRaw(source: .globalMonitor, eventType: "keyDown", keyCode: Int(event.keyCode), data1: nil, keyState: nil, action: .decrease)
                emit(.decrease, source: .globalMonitor)
            case kVK_F12:
                emitRaw(source: .globalMonitor, eventType: "keyDown", keyCode: Int(event.keyCode), data1: nil, keyState: nil, action: .increase)
                emit(.increase, source: .globalMonitor)
            default:
                emitRaw(source: .globalMonitor, eventType: "keyDown", keyCode: Int(event.keyCode), data1: nil, keyState: nil, action: nil)
                break
            }
            return
        }

        guard event.type == .systemDefined, event.subtype.rawValue == 8 else {
            return
        }
        let data = event.data1
        let keyCode = (data & 0xFFFF0000) >> 16
        let keyFlags = data & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        guard keyState == 0x0A else {
            emitRaw(source: .globalMonitor, eventType: "systemDefined", keyCode: keyCode, data1: data, keyState: keyState, action: nil)
            return
        }

        switch Int32(keyCode) {
        case NX_KEYTYPE_MUTE:
            emitRaw(source: .globalMonitor, eventType: "systemDefined", keyCode: keyCode, data1: data, keyState: keyState, action: .mute)
            emit(.mute, source: .globalMonitor)
        case NX_KEYTYPE_SOUND_DOWN:
            emitRaw(source: .globalMonitor, eventType: "systemDefined", keyCode: keyCode, data1: data, keyState: keyState, action: .decrease)
            emit(.decrease, source: .globalMonitor)
        case NX_KEYTYPE_SOUND_UP:
            emitRaw(source: .globalMonitor, eventType: "systemDefined", keyCode: keyCode, data1: data, keyState: keyState, action: .increase)
            emit(.increase, source: .globalMonitor)
        default:
            emitRaw(source: .globalMonitor, eventType: "systemDefined", keyCode: keyCode, data1: data, keyState: keyState, action: nil)
            break
        }
    }

    private func emitRaw(
        source: VolumeKeySource,
        eventType: String,
        keyCode: Int?,
        data1: Int?,
        keyState: Int?,
        action: VolumeKeyAction?
    ) {
        let record = RawHotKeyEventRecord(
            source: source,
            eventType: eventType,
            keyCode: keyCode,
            data1: data1,
            keyState: keyState,
            action: action
        )
        Task { @MainActor in
            onRawEvent?(record)
        }
    }

    private func emit(_ action: VolumeKeyAction, source: VolumeKeySource) {
        let now = CFAbsoluteTimeGetCurrent()
        if lastEmittedAction == action, now - lastEmitTime < 0.18 {
            return
        }
        lastEmittedAction = action
        lastEmitTime = now
        lastSource = source
        Task { @MainActor in
            onAction?(action, source)
        }
    }
}

private let mediaKeyEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.eventTapReceivedEvent = true
    return monitor.handle(event: event, type: type)
}

private let carbonHotKeyCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    let action: VolumeKeyAction?
    switch hotKeyID.id {
    case 10: action = .mute
    case 11: action = .decrease
    case 12: action = .increase
    default: action = nil
    }
    let record = RawHotKeyEventRecord(source: .carbon, eventType: "hotKeyPressed", keyCode: Int(hotKeyID.id), data1: nil, keyState: nil, action: action)
    Task { @MainActor in
        monitor.onRawEvent?(record)
    }
    monitor.handleCarbonHotKey(id: hotKeyID.id)
    return noErr
}
