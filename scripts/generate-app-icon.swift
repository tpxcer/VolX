#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("VolX-\(UUID().uuidString).iconset", isDirectory: true)

try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func rgba(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    let tileRect = CGRect(x: 60, y: 60, width: 904, height: 904)
    let tile = CGPath(roundedRect: tileRect, cornerWidth: 210, cornerHeight: 210, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 42, color: rgba(0, 0, 0, 0.42))
    context.addPath(tile)
    context.setFillColor(rgba(18, 21, 25))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [rgba(44, 49, 57), rgba(14, 17, 21)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 512, y: 964),
        end: CGPoint(x: 512, y: 60),
        options: []
    )
    context.setFillColor(rgba(255, 255, 255, 0.06))
    context.fillEllipse(in: CGRect(x: 130, y: 640, width: 760, height: 300))
    context.restoreGState()

    context.addPath(tile)
    context.setStrokeColor(rgba(255, 255, 255, 0.18))
    context.setLineWidth(5)
    context.strokePath()

    func drawBranch(end: CGPoint, control1: CGPoint, control2: CGPoint, color: CGColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 548, y: 512))
        path.addCurve(to: end, control1: control1, control2: control2)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: rgba(0, 0, 0, 0.36))
        context.addPath(path)
        context.setStrokeColor(color)
        context.setLineWidth(58)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
    }

    let cyan = rgba(69, 221, 207)
    let coral = rgba(255, 124, 101)
    drawBranch(
        end: CGPoint(x: 778, y: 682),
        control1: CGPoint(x: 640, y: 520),
        control2: CGPoint(x: 670, y: 660),
        color: cyan
    )
    drawBranch(
        end: CGPoint(x: 778, y: 342),
        control1: CGPoint(x: 640, y: 504),
        control2: CGPoint(x: 670, y: 364),
        color: coral
    )

    let speaker = CGMutablePath()
    speaker.move(to: CGPoint(x: 210, y: 442))
    speaker.addLine(to: CGPoint(x: 322, y: 442))
    speaker.addLine(to: CGPoint(x: 492, y: 314))
    speaker.addLine(to: CGPoint(x: 492, y: 710))
    speaker.addLine(to: CGPoint(x: 322, y: 582))
    speaker.addLine(to: CGPoint(x: 210, y: 582))
    speaker.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -9), blur: 22, color: rgba(0, 0, 0, 0.42))
    context.addPath(speaker)
    context.setFillColor(rgba(248, 250, 252))
    context.fillPath()
    context.restoreGState()

    context.addArc(
        center: CGPoint(x: 468, y: 512),
        radius: 132,
        startAngle: -0.82,
        endAngle: 0.82,
        clockwise: false
    )
    context.setStrokeColor(rgba(248, 250, 252, 0.9))
    context.setLineWidth(25)
    context.setLineCap(.round)
    context.strokePath()

    for (point, color) in [(CGPoint(x: 778, y: 682), cyan), (CGPoint(x: 778, y: 342), coral)] {
        context.setFillColor(rgba(255, 255, 255, 0.94))
        context.fillEllipse(in: CGRect(x: point.x - 43, y: point.y - 43, width: 86, height: 86))
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: point.x - 28, y: point.y - 28, width: 56, height: 56))
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

for variant in variants {
    let data = try drawIcon(pixels: variant.pixels)
    try data.write(to: iconset.appendingPathComponent(variant.name), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "--convert", "icns",
    iconset.path,
    "--output", resources.appendingPathComponent("AppIcon.icns").path
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}

print(resources.appendingPathComponent("AppIcon.icns").path)
