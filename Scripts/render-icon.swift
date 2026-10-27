#!/usr/bin/env swift
// StudyPilot's editable app-icon artwork. Uses only AppKit; no external assets.
// Run: swift Scripts/render-icon.swift /path/to/output-directory
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist/icon-artwork", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func polygon(_ points: [NSPoint]) -> NSBezierPath {
    let p = NSBezierPath(); p.move(to: points[0]); points.dropFirst().forEach { p.line(to: $0) }; p.close(); return p
}
func artwork(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    // Use top-left artwork coordinates, independent of output scale.
    context.cgContext.translateBy(x: 0, y: 1024)
    context.cgContext.scaleBy(x: 1, y: -1)

    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = color(0x07101C, alpha: 0.25); shadow.shadowBlurRadius = 16; shadow.shadowOffset = NSSize(width: 0, height: -8); shadow.set()
    color(0x152B3B).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x243F50), ending: color(0x102330))!.draw(in: tile, angle: 75)
    // A quiet edge gives the tile a tactile finish without a glossy highlight.
    color(0xFFFFFF, alpha: 0.13).setStroke(); tile.lineWidth = 2; tile.stroke()

    // Two pages share a firm baseline and an open spine. The right page folds
    // upward into a north-east pointer: study + direction in one silhouette.
    let left = NSBezierPath()
    left.move(to: NSPoint(x: 250, y: 340))
    left.curve(to: NSPoint(x: 492, y: 422), controlPoint1: NSPoint(x: 340, y: 328), controlPoint2: NSPoint(x: 422, y: 363))
    left.line(to: NSPoint(x: 492, y: 742))
    left.curve(to: NSPoint(x: 250, y: 665), controlPoint1: NSPoint(x: 414, y: 687), controlPoint2: NSPoint(x: 340, y: 653))
    left.close()
    let right = polygon([NSPoint(x: 526, y: 422), NSPoint(x: 786, y: 268), NSPoint(x: 728, y: 654), NSPoint(x: 526, y: 742)])
    NSGraphicsContext.saveGraphicsState()
    let paperShadow = NSShadow(); paperShadow.shadowColor = color(0x000A12, alpha: 0.30); paperShadow.shadowBlurRadius = 14; paperShadow.shadowOffset = NSSize(width: 0, height: -10); paperShadow.set()
    color(0xF7F4E9).setFill(); left.fill(); right.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0xFFFFFF), ending: color(0xE5EADD))!.draw(in: left, angle: 80)
    color(0xF7F4E9).setFill(); right.fill()
    // A single sea-glass fold makes the direction legible, even at Dock sizes.
    let fold = polygon([NSPoint(x: 526, y: 422), NSPoint(x: 786, y: 268), NSPoint(x: 614, y: 524)])
    NSGradient(starting: color(0xA9E2CA), ending: color(0x6CBDA7))!.draw(in: fold, angle: 30)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}
let sizes = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
let iconset = output.appendingPathComponent("StudyPilot.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try artwork(pixels: points * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}
try artwork(pixels: 1024).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("StudyPilot-icon.png"))
// Review sheet: real-size raster output on light and dark surroundings.
let review = NSImage(size: NSSize(width: 1000, height: 550))
review.lockFocus()
for row in 0..<2 {
    let y = CGFloat(row * 275)
    (row == 0 ? color(0xF2F2F0) : color(0x202326)).setFill()
    NSRect(x: 0, y: y, width: 1000, height: 275).fill()
    for (column, size) in [256,128,64,32,16].enumerated() {
        let center = [160,410,610,770,900][column]
        let image = NSImage(cgImage: artwork(pixels: size).cgImage!, size: NSSize(width: size, height: size))
        let side = CGFloat(size)
        let x = CGFloat(center) - side / 2
        let top = y + (CGFloat(275) - side) / 2 + 8
        image.draw(in: NSRect(x: x, y: top, width: side, height: side))
        let label = "\(size) px" as NSString
        label.draw(at: NSPoint(x: center - 18, y: Int(y) + 12), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: row == 0 ? color(0x666666) : color(0xBBBBBB)])
    }
}
review.unlockFocus()
try NSBitmapImageRep(data: review.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("StudyPilot-icon-review.png"))
print("Rendered iconset, 1024px artwork, and size review at \(output.path)")
