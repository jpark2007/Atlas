#!/usr/bin/env swift
//
//  make-dev-icon.swift — build the DEV-badged app icons used by Debug builds.
//
//  Reads the 1024pt master icon of each shipping AppIcon set, draws a diagonal
//  "DEV" ribbon across the bottom-right corner, and writes an AppIcon-Dev
//  appiconset next to it at every size the original declares.
//
//  Run from the repo root:   swift scripts/make-dev-icon.swift
//  Re-run whenever the shipping icons change; commit the regenerated assets.
//
import AppKit

struct IconSet {
    let source: String        // existing .appiconset
    let destination: String   // AppIcon-Dev .appiconset to write
    let master: String        // 1024x1024 png inside `source`
    /// filename -> pixel size. Contents.json is rewritten from the source with
    /// filenames remapped into the destination set.
    let pixelSizes: [String: Int]
}

let sets = [
    IconSet(
        source: "Atlas/Assets.xcassets/AppIcon.appiconset",
        destination: "Atlas/Assets.xcassets/AppIcon-Dev.appiconset",
        master: "icon_1024.png",
        pixelSizes: ["icon_16.png": 16, "icon_32.png": 32, "icon_64.png": 64,
                     "icon_128.png": 128, "icon_256.png": 256,
                     "icon_512.png": 512, "icon_1024.png": 1024]
    ),
    IconSet(
        source: "AtlasMobile/Assets.xcassets/AppIcon.appiconset",
        destination: "AtlasMobile/Assets.xcassets/AppIcon-Dev.appiconset",
        master: "AppIcon-1024.png",
        pixelSizes: ["AppIcon-1024.png": 1024]
    ),
]

func loadMaster(_ path: String) -> NSBitmapImageRep {
    guard let data = FileManager.default.contents(atPath: path),
          let rep = NSBitmapImageRep(data: data) else {
        fatalError("cannot read master icon at \(path)")
    }
    return rep
}

/// Draw `master` at `size`x`size` with a diagonal DEV ribbon in the lower-right.
func badged(_ master: NSBitmapImageRep, size: Int) -> Data {
    let s = CGFloat(size)
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("cannot create bitmap context") }

    let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc

    ctx.interpolationQuality = .high
    if let cg = master.cgImage {
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: s, height: s))
    }

    // Ribbon: a 45° band across the bottom-right corner, clipped to the icon's
    // own alpha so it never spills outside the rounded silhouette.
    let bandThickness = s * 0.26
    ctx.saveGState()
    if let cg = master.cgImage {
        ctx.clip(to: CGRect(x: 0, y: 0, width: s, height: s), mask: cg)
    }
    ctx.translateBy(x: s * 0.80, y: s * 0.20)
    ctx.rotate(by: .pi / 4)                    // band runs bottom-left ↗ top-right
    let band = CGRect(x: -s, y: -bandThickness / 2, width: 2 * s, height: bandThickness)
    ctx.setFillColor(NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.25, alpha: 1).cgColor)
    ctx.fill(band)

    // "DEV" — only legible above ~48px; below that the band alone is the signal.
    if size >= 48 {
        let fontSize = bandThickness * 0.62
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: NSColor.white,
            .kern: fontSize * 0.06,
        ]
        let text = NSAttributedString(string: "DEV", attributes: attrs)
        let m = text.size()
        text.draw(at: CGPoint(x: -m.width / 2, y: -m.height / 2))
    }
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

    guard let image = ctx.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { fatalError("cannot encode png") }
    return png
}

let fm = FileManager.default
for set in sets {
    let master = loadMaster("\(set.source)/\(set.master)")
    try? fm.createDirectory(atPath: set.destination, withIntermediateDirectories: true)

    for (name, px) in set.pixelSizes.sorted(by: { $0.key < $1.key }) {
        let out = "\(set.destination)/\(name)"
        try! badged(master, size: px).write(to: URL(fileURLWithPath: out))
        print("wrote \(out) (\(px)px)")
    }

    // Contents.json is copied verbatim — filenames are identical inside the new set.
    let contents = "\(set.source)/Contents.json"
    let destContents = "\(set.destination)/Contents.json"
    try? fm.removeItem(atPath: destContents)
    try! fm.copyItem(atPath: contents, toPath: destContents)
    print("wrote \(destContents)")
}
