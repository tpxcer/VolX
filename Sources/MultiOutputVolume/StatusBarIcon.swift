import AppKit

@MainActor
enum StatusBarIcon {
    static let size = NSSize(width: 20, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.translateBy(x: -0.7, y: -0.9)
            context.scaleBy(x: 1.15, y: 1.1)
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            let speaker = CGMutablePath()
            speaker.move(to: CGPoint(x: 0.8, y: 6.4))
            speaker.addLine(to: CGPoint(x: 3.8, y: 6.4))
            speaker.addLine(to: CGPoint(x: 8.5, y: 2.9))
            speaker.addLine(to: CGPoint(x: 8.5, y: 15.1))
            speaker.addLine(to: CGPoint(x: 3.8, y: 11.6))
            speaker.addLine(to: CGPoint(x: 0.8, y: 11.6))
            speaker.closeSubpath()
            context.addPath(speaker)
            context.fillPath()

            context.addArc(
                center: CGPoint(x: 8.3, y: 9),
                radius: 3.4,
                startAngle: -0.72,
                endAngle: 0.72,
                clockwise: false
            )
            context.setLineWidth(1.2)
            context.strokePath()

            func drawBranch(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 10.4, y: 9))
                path.addCurve(to: end, control1: control1, control2: control2)
                context.addPath(path)
                context.setLineWidth(1.7)
                context.strokePath()
                context.fillEllipse(
                    in: CGRect(x: end.x - 1.15, y: end.y - 1.15, width: 2.3, height: 2.3)
                )
            }

            drawBranch(
                to: CGPoint(x: 16.3, y: 13.5),
                control1: CGPoint(x: 12.7, y: 9.1),
                control2: CGPoint(x: 13.8, y: 13.5)
            )
            drawBranch(
                to: CGPoint(x: 16.3, y: 4.5),
                control1: CGPoint(x: 12.7, y: 8.9),
                control2: CGPoint(x: 13.8, y: 4.5)
            )
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "VolX 统一音量"
        return image
    }
}
