#!/usr/bin/env swift
// Generates AppIcon.iconset PNGs for Quill.app
// Uses Core Graphics directly (no NSApplication needed)
import Foundation
import CoreGraphics
import ImageIO

// MARK: - Entry point

func makeIconData(size: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Scale from 1024×1024 design space
    let s = CGFloat(size) / 1024.0
    ctx.scaleBy(x: s, y: s)

    drawBackground(ctx: ctx)
    drawQuill(ctx: ctx)

    guard let image = ctx.makeImage() else { return nil }

    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

// MARK: - Background

func drawBackground(ctx: CGContext) {
    ctx.saveGState()

    // Clip to squircle
    let roundedRect = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
        cornerWidth: 230, cornerHeight: 230, transform: nil
    )
    ctx.addPath(roundedRect)
    ctx.clip()

    // Subtle warm gradient: lighter top (#F4EDDA), slightly darker bottom (#EAE1CC)
    // CG y-up: start=(bottom), end=(top)
    let colors = [
        CGColor(red: 0.918, green: 0.882, blue: 0.800, alpha: 1.0),  // bottom
        CGColor(red: 0.957, green: 0.929, blue: 0.855, alpha: 1.0),  // top
    ] as CFArray
    let locs: [CGFloat] = [0.0, 1.0]
    let gradient = CGGradient(colorsSpace: colorSpace(), colors: colors, locations: locs)!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 512, y: 0),
        end: CGPoint(x: 512, y: 1024),
        options: []
    )

    ctx.restoreGState()
}

func colorSpace() -> CGColorSpace { CGColorSpaceCreateDeviceRGB() }

// MARK: - Quill

func drawQuill(ctx: CGContext) {
    let quillPath = buildQuillPath()
    let spinePath = buildSpinePath()

    // Rotate -42° (clockwise in y-up) around center (512, 512)
    // → nib lower-left, feather tip upper-right
    var xf = CGAffineTransform(translationX: 512, y: 512)
        .rotated(by: -42.0 * .pi / 180.0)
        .translatedBy(x: -512, y: -512)

    guard let rotatedQuill = quillPath.copy(using: &xf),
          let rotatedSpine = spinePath.copy(using: &xf) else { return }

    // --- Fill with drop shadow ---
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 10, height: -18),
        blur: 34,
        color: CGColor(red: 0.07, green: 0.12, blue: 0.25, alpha: 0.28)
    )
    ctx.setFillColor(CGColor(red: 0.102, green: 0.173, blue: 0.322, alpha: 1.0))  // #1A2C52
    ctx.addPath(rotatedQuill)
    ctx.fillPath()
    ctx.restoreGState()

    // --- Spine highlight clipped to quill interior ---
    ctx.saveGState()
    ctx.addPath(rotatedQuill)
    ctx.clip()
    ctx.setStrokeColor(CGColor(red: 0.18, green: 0.28, blue: 0.46, alpha: 0.50))
    ctx.setLineWidth(5)
    ctx.addPath(rotatedSpine)
    ctx.strokePath()
    ctx.restoreGState()
}

func buildQuillPath() -> CGPath {
    // AppKit/CG y-up, 1024x1024 canvas, quill vertical before rotation
    // Nib tip: y=178 (bottom, sharp point), feather tip: y=850 (top, sharp point)
    // Vane max width: +/-158px from centerline at y=598
    let p = CGMutablePath()

    p.move(to: CGPoint(x: 512, y: 178))                        // nib tip

    // Left calamus (thin shaft)
    p.addCurve(to: CGPoint(x: 500, y: 378),
               control1: CGPoint(x: 507, y: 255),
               control2: CGPoint(x: 502, y: 316))

    // Left vane opens outward
    p.addCurve(to: CGPoint(x: 354, y: 598),
               control1: CGPoint(x: 494, y: 430),
               control2: CGPoint(x: 370, y: 512))

    // Left vane tapers sharply to pointed feather tip
    p.addCurve(to: CGPoint(x: 512, y: 850),
               control1: CGPoint(x: 310, y: 688),
               control2: CGPoint(x: 476, y: 844))

    // Right vane opens from pointed feather tip
    p.addCurve(to: CGPoint(x: 670, y: 598),
               control1: CGPoint(x: 548, y: 844),
               control2: CGPoint(x: 716, y: 690))

    // Right vane narrows to calamus
    p.addCurve(to: CGPoint(x: 524, y: 378),
               control1: CGPoint(x: 722, y: 508),
               control2: CGPoint(x: 536, y: 436))

    // Right calamus back to nib tip
    p.addCurve(to: CGPoint(x: 512, y: 178),
               control1: CGPoint(x: 522, y: 316),
               control2: CGPoint(x: 517, y: 255))

    p.closeSubpath()
    return p
}

func buildSpinePath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 512, y: 200))
    p.addLine(to: CGPoint(x: 512, y: 838))
    return p
}

// MARK: - Main

import UniformTypeIdentifiers

let iconsetDir = "AppIcon.iconset"
try! FileManager.default.createDirectory(
    atPath: iconsetDir, withIntermediateDirectories: true, attributes: nil)

let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

print("Generating icon sizes...")
var ok = 0
for (size, name) in sizes {
    guard let data = makeIconData(size: size) else {
        print("  ✗ Failed at \(size)px"); continue
    }
    let path = "\(iconsetDir)/\(name)"
    try! data.write(to: URL(fileURLWithPath: path))
    print("  ✓ \(name) (\(size)px)")
    ok += 1
}
print("\(ok)/\(sizes.count) files written to \(iconsetDir)/")
