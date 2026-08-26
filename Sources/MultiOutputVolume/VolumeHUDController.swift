import AppKit
import SwiftUI

@MainActor
final class VolumeHUDController {
    private let panelSize = NSSize(width: 300, height: 72)
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func show(title: String, volume: Float, isMuted: Bool, anchorRect: NSRect?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: VolumeHUDView(title: title, volume: volume, isMuted: isMuted))
        position(panel, anchorRect: anchorRect)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.fadeOut() }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: workItem)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
        return panel
    }

    private func position(_ panel: NSPanel, anchorRect: NSRect?) {
        let screen = anchorRect.flatMap { anchor in
            NSScreen.screens.first { $0.frame.intersects(anchor) }
        } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(Self.origin(panelSize: panel.frame.size, anchorRect: anchorRect, visibleFrame: frame))
    }

    static func origin(panelSize: NSSize, anchorRect: NSRect?, visibleFrame: NSRect) -> NSPoint {
        guard let anchorRect else {
            return NSPoint(
                x: visibleFrame.maxX - panelSize.width - 18,
                y: visibleFrame.maxY - panelSize.height - 18
            )
        }
        let x = min(
            max(anchorRect.minX, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8
        )
        let y = max(visibleFrame.minY + 8, anchorRect.minY - panelSize.height - 8)
        return NSPoint(x: x, y: y)
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        }
    }
}

struct VolumeHUDView: View {
    let title: String
    let volume: Float
    let isMuted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(Int((volume * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 9) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.16))
                        Capsule()
                            .fill(.primary.opacity(isMuted ? 0 : 0.72))
                            .frame(width: proxy.size.width * CGFloat(isMuted ? 0 : volume))
                    }
                }
                .frame(height: 5)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 300, height: 72)
        .background {
            GlassBackground(material: .hudWindow)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.3), lineWidth: 0.75)
        }
    }
}
