import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController {
    private let model: VolumeModel
    private let statusItem: NSStatusItem
    private var panel: NSPanel?
    private var outsideGlobalClickMonitor: Any?
    private var outsideLocalClickMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    init(model: VolumeModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()
        model.hudAnchorProvider = { [weak self] in
            self?.statusItemImageFrameOnScreen()
        }
        bind()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = StatusBarIcon.make(volume: model.volume, isMuted: model.isMuted)
        button.imageScaling = .scaleNone
        button.title = ""
        button.setAccessibilityTitle("VolX")
        button.setAccessibilityLabel("VolX 统一音量")
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func bind() {
        model.$volume
            .combineLatest(model.$isMuted)
            .sink { [weak self] _, _ in
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        model.$airPlayDevices
            .dropFirst()
            .sink { [weak self] _ in
                self?.resizeVisiblePanel()
            }
            .store(in: &cancellables)

        model.$devices.combineLatest(model.$selectedDeviceUIDs, model.$activeOutputUID)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.resizeVisiblePanel() }
            .store(in: &cancellables)
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        button.image = StatusBarIcon.make(volume: model.volume, isMuted: model.isMuted)
        button.toolTip = "\(model.controlTitle) \(Int((model.volume * 100).rounded()))%"
        button.setAccessibilityValue(button.toolTip)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            hidePanel(nil)
            showContextMenu(relativeTo: button)
            return
        }
        model.refreshDevices()
        if let panel, panel.isVisible {
            hidePanel(sender)
        } else {
            showPanel(relativeTo: button)
        }
    }

    func showPanelForTesting() {
        guard let button = statusItem.button else { return }
        model.refreshDevices()
        showPanel(relativeTo: button)
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        let panelSize = currentPanelSize
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: MenuPanelView(model: model))
        panel.setContentSize(panelSize)
        if let window = button.window,
           let buttonFrame = statusItemImageFrameOnScreen() {
            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            panel.setFrameOrigin(
                Self.panelOrigin(
                    panelSize: panelSize,
                    anchorRect: buttonFrame,
                    visibleFrame: visible
                )
            )
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        installOutsideClickMonitor(for: panel)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: currentPanelSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "VolX"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        return panel
    }

    private var currentPanelSize: NSSize {
        NSSize(
            width: MenuPanelView.panelWidth,
            height: MenuPanelView.panelHeight(outputRowCount: model.visibleOutputRowCount,
                                             balanceCount: model.balanceDevices.count)
        )
    }

    private func resizeVisiblePanel() {
        guard let panel, panel.isVisible else { return }
        let oldTop = panel.frame.maxY
        let panelSize = currentPanelSize
        panel.setContentSize(panelSize)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: oldTop - panelSize.height))
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
        let menu = NSMenu()
        let launchItem = NSMenuItem(
            title: "登录时启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = model.launchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 VolX",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button)
    }

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLogin(!model.launchAtLoginEnabled)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func hidePanel(_ sender: Any?) {
        panel?.orderOut(sender)
        removeOutsideClickMonitor()
    }

    private func installOutsideClickMonitor(for panel: NSPanel) {
        removeOutsideClickMonitor()
        outsideGlobalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let panel, panel.isVisible else { return }
            if !panel.frame.contains(Self.screenLocation(for: event)) {
                Task { @MainActor in
                    self?.hidePanel(nil)
                }
            }
        }
        outsideLocalClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let panel, panel.isVisible else { return event }
            if !panel.frame.contains(Self.screenLocation(for: event)) {
                self?.hidePanel(nil)
            }
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideGlobalClickMonitor {
            NSEvent.removeMonitor(outsideGlobalClickMonitor)
        }
        if let outsideLocalClickMonitor {
            NSEvent.removeMonitor(outsideLocalClickMonitor)
        }
        outsideGlobalClickMonitor = nil
        outsideLocalClickMonitor = nil
    }

    private static func screenLocation(for event: NSEvent) -> NSPoint {
        if let window = event.window {
            let rect = NSRect(origin: event.locationInWindow, size: .zero)
            return window.convertToScreen(rect).origin
        }
        return NSEvent.mouseLocation
    }

    static func panelOrigin(
        panelSize: NSSize,
        anchorRect: NSRect,
        visibleFrame: NSRect
    ) -> NSPoint {
        let x = min(
            max(anchorRect.minX, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8
        )
        let preferredY = anchorRect.minY - panelSize.height - 8
        return NSPoint(x: x, y: max(visibleFrame.minY + 8, preferredY))
    }

    private func statusItemFrameOnScreen() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    private func statusItemImageFrameOnScreen() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? button.bounds
        let frameInWindow = button.convert(imageRect, to: nil)
        return window.convertToScreen(frameInWindow)
    }
}
