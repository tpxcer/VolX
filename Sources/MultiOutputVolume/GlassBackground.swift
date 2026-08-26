import AppKit
import SwiftUI

struct GlassBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.style = .regular
            view.cornerRadius = material == .hudWindow ? 18 : 16
            if #available(macOS 27.0, *) {
                view.effectIsInteractive = false
            }
            return view
        }

        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.style = .regular
            glass.cornerRadius = material == .hudWindow ? 18 : 16
            return
        }
        guard let visualEffect = view as? NSVisualEffectView else { return }
        visualEffect.material = material
        visualEffect.state = .active
    }
}
