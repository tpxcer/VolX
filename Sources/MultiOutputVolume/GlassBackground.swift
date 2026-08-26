import AppKit
import SwiftUI

struct GlassBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.style = .regular
            view.cornerRadius = cornerRadius
            if #available(macOS 27.0, *) {
                view.effectIsInteractive = false
            }
            applyClipping(to: view)
            return view
        }

        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        applyClipping(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            applyClipping(to: glass)
            return
        }
        guard let visualEffect = view as? NSVisualEffectView else { return }
        visualEffect.material = material
        visualEffect.state = .active
        applyClipping(to: visualEffect)
    }

    private func applyClipping(to view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
