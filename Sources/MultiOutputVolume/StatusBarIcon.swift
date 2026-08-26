import AppKit

@MainActor
enum StatusBarIcon {
    static let size = NSSize(width: 26, height: 18)
    static let maximumSymbolName = "speaker.wave.3"
    static let currentSymbolName = "speaker.wave.3.fill"
    static let maximumLayerOpacity: CGFloat = 0.1
    static let currentLayerPasses = 2

    static func make(volume: Float, isMuted: Bool) -> NSImage {
        let level = normalizedLevel(volume: volume, isMuted: isMuted)
        let configuration = NSImage.SymbolConfiguration(pointSize: 15.5, weight: .regular)
        let maximumSymbol = NSImage(
            systemSymbolName: maximumSymbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
        let currentSymbol = NSImage(
            systemSymbolName: currentSymbolName,
            variableValue: level,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)

        let image = NSImage(size: size, flipped: false) { bounds in
            guard let maximumSymbol, let currentSymbol else { return false }
            let targetRect = contentRect(in: bounds, sourceSize: maximumSymbol.size)
            maximumSymbol.draw(
                in: targetRect,
                from: .zero,
                operation: .sourceOver,
                fraction: maximumLayerOpacity,
                respectFlipped: true,
                hints: nil
            )
            for _ in 0..<currentLayerPasses {
                currentSymbol.draw(
                    in: targetRect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
            }
            if isMuted {
                drawMuteSlash(in: targetRect)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = isMuted
            ? "VolX 已静音"
            : "VolX 音量 \(Int((volume * 100).rounded()))%"
        return image
    }

    static func normalizedLevel(volume: Float, isMuted: Bool) -> Double {
        isMuted ? 0 : Double(min(max(volume, 0), 1))
    }

    static func contentRect(in bounds: NSRect, sourceSize: NSSize) -> NSRect {
        return NSRect(
            x: bounds.midX - sourceSize.width / 2,
            y: bounds.midY - sourceSize.height / 2,
            width: sourceSize.width,
            height: sourceSize.height
        )
    }

    private static func drawMuteSlash(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.7)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: rect.minX + 5.2, y: rect.maxY - 1.2))
        context.addLine(to: CGPoint(x: rect.maxX - 3.2, y: rect.minY + 1.2))
        context.strokePath()
        context.restoreGState()
    }
}
