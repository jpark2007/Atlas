#!/usr/bin/env swift
//
//  gen_app_icon.swift — Atlas macOS AppIcon generator
//
//  Draws a clean, simple Atlas mark — an abstract bloom (8 rounded petals in the
//  orange brand accent with a deeper center) on a soft warm rounded-square
//  background — and emits PNGs at every macOS icon pixel size into
//  Atlas/Assets.xcassets/AppIcon.appiconset/.
//
//  Run from the repo root:   swift tools/gen_app_icon.swift
//
//  No SVG rasterizer required: rendering is pure offscreen AppKit/CoreGraphics
//  (NSBitmapImageRep), so it works headless (no window server needed).
//
import AppKit
import Foundation

// MARK: - Brand palette (matches AtlasTheme)

private func srgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

private let accent     = srgb(0xff, 0x8c, 0x42) // AtlasTheme.Colors.accent
private let accentDeep = srgb(0xff, 0x6b, 0x1a) // AtlasTheme.Colors.accentDeep
private let bgTop      = srgb(0xff, 0xf1, 0xe2) // soft warm cream
private let bgBottom   = srgb(0xff, 0xdb, 0xbb) // peach
private let centerCol  = srgb(0xff, 0xb1, 0x5a) // warm bloom center

// MARK: - Render one icon at `pixels` × `pixels`

private func makeIcon(_ pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)

    // Soft rounded-square background (Apple squircle ≈ 22.37% corner radius).
    let corner = s * 0.2237
    let bgRect = NSRect(x: 0, y: 0, width: s, height: s)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: corner, yRadius: corner)
    if let bgGrad = NSGradient(starting: bgTop, ending: bgBottom) {
        bgGrad.draw(in: bgPath, angle: -90)
    } else {
        bgTop.setFill(); bgPath.fill()
    }

    // Bloom: 8 rounded petals radiating from the center.
    let center = NSPoint(x: s / 2, y: s / 2)
    let petalGrad = NSGradient(starting: accent, ending: accentDeep)
    let petalCount = 8
    let petalW = s * 0.165
    let petalH = s * 0.300
    let orbit  = s * 0.085   // gap between icon center and each petal's base

    for i in 0 ..< petalCount {
        let angle = CGFloat(i) / CGFloat(petalCount) * .pi * 2
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: center.x, yBy: center.y)
        t.rotate(byRadians: angle)
        t.concat()

        let petalRect = NSRect(x: -petalW / 2, y: orbit, width: petalW, height: petalH)
        let petal = NSBezierPath(ovalIn: petalRect)
        if let petalGrad { petalGrad.draw(in: petal, angle: 90) }
        else { accent.setFill(); petal.fill() }

        NSGraphicsContext.restoreGraphicsState()
    }

    // Deeper center disc.
    let cr = s * 0.130
    let centerPath = NSBezierPath(ovalIn: NSRect(x: center.x - cr, y: center.y - cr,
                                                 width: cr * 2, height: cr * 2))
    centerCol.setFill()
    centerPath.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "gen_app_icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try data.write(to: url)
}

// MARK: - Output

// Resolve the appiconset relative to this script so it works from any cwd.
let scriptURL = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
let repoRoot  = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outDir    = repoRoot
    .appendingPathComponent("Atlas/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// macOS AppIcon slots: 16/32/128/256/512 at @1x and @2x.
let slots: [(name: String, px: Int)] = [
    ("icon_16x16",      16),  ("icon_16x16@2x",   32),
    ("icon_32x32",      32),  ("icon_32x32@2x",   64),
    ("icon_128x128",   128),  ("icon_128x128@2x", 256),
    ("icon_256x256",   256),  ("icon_256x256@2x", 512),
    ("icon_512x512",   512),  ("icon_512x512@2x", 1024),
]

for slot in slots {
    let rep = makeIcon(slot.px)
    let url = outDir.appendingPathComponent("\(slot.name).png")
    try writePNG(rep, to: url)
    print("wrote \(slot.name).png  (\(slot.px)×\(slot.px))")
}

print("Done → \(outDir.path)")
