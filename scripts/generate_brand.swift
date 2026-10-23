// Reproducible native assets from the approved plug vector. No network or fonts.
// Run from the repository root: swift scripts/generate_brand.swift
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func plugPath(in rect: CGRect) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: .init(x: 8, y: 3)); p.line(to: .init(x: 8, y: 8))
    p.move(to: .init(x: 16, y: 3)); p.line(to: .init(x: 16, y: 8))
    p.move(to: .init(x: 6, y: 8)); p.line(to: .init(x: 18, y: 8)); p.line(to: .init(x: 18, y: 12))
    p.curve(to: .init(x: 6, y: 12), controlPoint1: .init(x: 18, y: 20), controlPoint2: .init(x: 6, y: 20))
    p.line(to: .init(x: 6, y: 8)); p.move(to: .init(x: 12, y: 18)); p.line(to: .init(x: 12, y: 21))
    var transform = AffineTransform(); transform.translate(x: rect.minX, y: rect.minY); transform.scale(x: rect.width / 24, y: rect.height / 24)
    p.transform(using: transform); p.lineWidth = rect.width / 24 * 1.45; p.lineCapStyle = .round; p.lineJoinStyle = .round
    return p
}
func png(size: Int, icon: Bool) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot allocate bitmap") }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let cg = context.cgContext; cg.translateBy(x: 0, y: CGFloat(size)); cg.scaleBy(x: 1, y: -1)
    let side = CGFloat(size)
    if icon {
        let box = CGRect(x: side * 0.08, y: side * 0.08, width: side * 0.84, height: side * 0.84)
        let shape = NSBezierPath(roundedRect: box, xRadius: side * 0.19, yRadius: side * 0.19)
        NSGradient(starting: color(0x343C37), ending: color(0x141719))!.draw(in: shape, angle: 75)
        color(0x81725B).withAlphaComponent(0.55).setStroke(); shape.lineWidth = max(0.8, side * 0.002); shape.stroke()
        color(0xE5AE82).setStroke(); plugPath(in: CGRect(x: side * 0.2, y: side * 0.2, width: side * 0.6, height: side * 0.6)).stroke()
    } else {
        NSColor.black.setStroke(); plugPath(in: CGRect(x: 0, y: 0, width: side, height: side)).stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
    return data
}
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let icons = root.appendingPathComponent("Sources/PortPilot/Assets.xcassets/AppIcon.appiconset")
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: icons.appendingPathComponent("Contents.json"))) as! [String: Any]
let images = manifest["images"] as! [[String: String]]
let iconNames = try FileManager.default.contentsOfDirectory(atPath: icons.path).filter { $0.hasPrefix("icon_") && $0.hasSuffix(".png") }
for name in iconNames {
    let stem = name.dropFirst(5).split(separator: "x")[0]
    guard let points = Int(stem) else { fatalError("Unexpected icon filename: \(name)") }
    let pixels = points * (name.contains("@2x") ? 2 : 1)
    try png(size: pixels, icon: true).write(to: icons.appendingPathComponent(name), options: .atomic)
}
let menu = root.appendingPathComponent("Sources/PortPilot/Assets.xcassets/MenuBarIcon.imageset")
var entries: [[String: String]] = []
for scale in 1...3 {
    let name = "portpilot-plug@\(scale)x.png"
    try png(size: 20 * scale, icon: false).write(to: menu.appendingPathComponent(name), options: .atomic)
    entries.append(["idiom": "universal", "scale": "\(scale)x", "filename": name])
}
try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1], "properties": ["template-rendering-intent": "template"]], options: [.prettyPrinted, .sortedKeys]).write(to: menu.appendingPathComponent("Contents.json"), options: .atomic)
try png(size: 40, icon: false).write(to: root.appendingPathComponent("Sources/PortPilot/menubar_icon.png"), options: .atomic)
try png(size: 512, icon: true).write(to: root.appendingPathComponent("assets/brand/portpilot-app-icon.png"), options: .atomic)
print("Generated \(iconNames.count) app icons (\(images.count) active entries), 3 template menu icons, and brand preview.")
