@preconcurrency import AppKit

private let systemDefinedEventType = CGEventType(rawValue: 14)!

enum VolumeKeySource: String, Sendable {
    case eventTap
    // Retained for old diagnostics/self-tests; never installed as input paths.
    case globalMonitor
    case carbon
    case selfTest
}

struct RawHotKeyEventRecord: Sendable {
    let source: VolumeKeySource
    let eventType: String
    let keyCode: Int?
    let data1: Int?
    let keyState: Int?
    let action: VolumeKeyAction?
    var displayText: String {
        "source=\(source.rawValue) type=\(eventType) action=\(String(describing: action))"
    }
}

final class MediaKeyMonitor: @unchecked Sendable {
    var onAction: (@MainActor (VolumeKeyAction, VolumeKeySource) -> Void)?
    var onRawEvent: (@MainActor (RawHotKeyEventRecord) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapRetryTimer: Timer?
    private(set) var eventTapCreated = false
    var eventTapReceivedEvent = false
    private(set) var accessibilityTrusted = false
    let globalMonitorCreated = false
    let globalMonitorReceivedEvent = false
    let carbonRegisteredIDs: Set<UInt32> = []
    private(set) var lastSource: VolumeKeySource?

    func start() {
        stop()
        eventTapReceivedEvent = false
        lastSource = nil
        accessibilityTrusted = AXIsProcessTrusted()
        if !accessibilityTrusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        startEventTap()
        if !eventTapCreated { startEventTapRetry() }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        eventTapCreated = false
        eventTapRetryTimer?.invalidate()
        eventTapRetryTimer = nil
    }

    private func startEventTap() {
        guard eventTap == nil else { return }
        accessibilityTrusted = AXIsProcessTrusted()
        guard accessibilityTrusted else { return }
        // Only NX media events. Never subscribe to keyDown/keyUp or register F keys.
        let mask = CGEventMask(1) << systemDefinedEventType.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: mediaKeyEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
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
            guard let self else { timer.invalidate(); return }
            self.startEventTap()
            if self.eventTapCreated {
                timer.invalidate()
                self.eventTapRetryTimer = nil
            }
        }
        eventTapRetryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // Internal for native event integration tests. Invoked only on the main run loop.
    func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              let decision = NativeVolumeKey.decode(type: type.rawValue,
                  subtype: Int(nsEvent.subtype.rawValue), data: nsEvent.data1,
                  modifiers: UInt64(nsEvent.modifierFlags.rawValue)) else {
            return Unmanaged.passUnretained(event)
        }
        if let action = decision.action {
            lastSource = .eventTap
            // Only recognized volume actions are logged, never ordinary keycodes/data.
            let record = RawHotKeyEventRecord(source: .eventTap, eventType: "systemDefined",
                keyCode: nil, data1: nil, keyState: nil, action: action)
            Task { @MainActor in
                self.onRawEvent?(record)
                self.onAction?(action, .eventTap)
            }
        }
        // Exclusively consume both press/repeat and release; no competing fallback writes.
        return nil
    }
}

private let mediaKeyEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.eventTapReceivedEvent = true
    return monitor.handle(event: event, type: type)
}
