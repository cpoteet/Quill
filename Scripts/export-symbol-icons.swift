// Rebuilds site/images/symbols/*.svg: the SF Symbols the user guide shows for
// the window-toolbar buttons and the post status badges, one black-filled
// vector SVG per icon. The guide draws each as a CSS mask filled with the
// surrounding text colour (or a status colour), so it works in light and dark
// mode alike.
//
//   swift Scripts/export-symbol-icons.swift
//
// Needs poppler's pdftocairo (`brew install poppler`). Each symbol is drawn by
// SwiftUI into a PDF, where it stays vector (AppKit's NSImage.draw rasterises
// it), and pdftocairo turns the PDF into SVG paths.
//
// Two wrinkles, both places where the PDF would otherwise carry a bitmap mask:
//
// - `.plain` symbols whose arrow overlaps the base shape (tray.and.arrow.down,
//   square.and.arrow.up, icloud.and.arrow.up) clear a gap in the base around
//   the arrow. The script drops the bitmap and cuts the arrow's outline, grown
//   by `clearance`, out of the base path.
// - `.cutout` symbols (the *.circle.fill status badges) knock their glyph out
//   of the filled circle. Drawn in palette mode, the glyph and the circle come
//   out as two separate paths, and the script cuts one out of the other.
//
// Both cuts are CGPath boolean operations, so every icon ships as plain
// paths. Never an SVG <mask>: WebKit draws one at the SVG's own 18 px size,
// so masked icons were blurry in Safari on Retina.
//
// Anything else that comes out as a bitmap stops the script rather than
// shipping a raster.
//
// The toolbar list mirrors the Image(systemName:) calls on the window toolbar
// in SidebarView, PostEditorView (including publishButtonIcon) and
// MediaLibraryView; the status list mirrors statusSymbol() in
// DesignSystem.swift. When one changes there, change it here and run this again.
//
// SF Symbols are Apple's artwork, used under Apple's SF Symbols terms.

import Foundation
import SwiftUI

enum Kind { case plain, cutout }

let symbols: [(id: String, name: String, kind: Kind)] = [
    // Window toolbar
    ("sidebar-left", "sidebar.left", .plain),
    ("refresh", "arrow.clockwise", .plain),
    ("new", "plus", .plain),
    ("save-locally", "tray.and.arrow.down", .plain),
    ("revert", "arrow.uturn.backward", .plain),
    ("preview", "eye", .plain),
    ("share", "square.and.arrow.up", .plain),
    ("publish-draft", "icloud.and.arrow.up", .plain),
    ("publish-update", "arrow.up.circle", .plain),
    ("publish", "paperplane", .plain),
    ("sidebar-right", "sidebar.right", .plain),
    ("back", "chevron.backward", .plain),
    // Post status badges (statusSymbol in DesignSystem.swift)
    ("status-draft", "pencil.circle.fill", .cutout),
    ("status-pending", "ellipsis.circle.fill", .cutout),
    ("status-publish", "checkmark.circle.fill", .cutout),
    ("status-future", "clock.circle.fill", .cutout),
    ("status-private", "lock.circle.fill", .cutout),
    ("status-local", "tray.circle.fill", .cutout),
]

/// Gap left around an overlapping arrow, in points at the 16 pt render size.
/// Matched by eye against macOS's own rendering at 8x.
let clearance = 1.0

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outputDir = root.appendingPathComponent("site/images/symbols")
let work = FileManager.default.temporaryDirectory.appendingPathComponent("quill-symbol-icons-\(getpid())")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("export-symbol-icons: \(message)\n".utf8))
    exit(1)
}

guard let pdftocairo = ["/opt/homebrew/bin/pdftocairo", "/usr/local/bin/pdftocairo"]
    .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
else { fail("pdftocairo not found; run `brew install poppler`") }

// Palette colours that mark which path is which in a .cutout render.
let glyphFill = #"fill="rgb(100%, 0%, 0%)""#, baseFill = #"fill="rgb(0%, 0%, 100%)""#

@MainActor func renderPDF(_ name: String, kind: Kind, to url: URL) {
    guard NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else {
        fail("no SF Symbol named \(name) on this macOS")
    }
    let image = Image(systemName: name).font(.system(size: 16, weight: .regular))
    let view: AnyView = switch kind {
    case .plain:
        AnyView(image.symbolRenderingMode(.monochrome).foregroundStyle(Color(red: 0, green: 0, blue: 0)))
    case .cutout:
        AnyView(image.symbolRenderingMode(.palette)
            .foregroundStyle(Color(red: 1, green: 0, blue: 0), Color(red: 0, green: 0, blue: 1)))
    }
    ImageRenderer(content: view).render { size, draw in
        var box = CGRect(origin: .zero, size: size)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { fail("cannot write \(url.path)") }
        ctx.beginPDFPage(nil)
        draw(ctx)
        ctx.endPDFPage()
        ctx.closePDF()
    }
}

func convert(_ pdf: URL, to svg: URL) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: pdftocairo)
    task.arguments = ["-svg", pdf.path, svg.path]
    do { try task.run() } catch { fail("pdftocairo: \(error)") }
    task.waitUntilExit()
    if task.terminationStatus != 0 { fail("pdftocairo failed on \(pdf.lastPathComponent)") }
}

func matches(_ pattern: String, in text: String) -> [[String]] {
    let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
        (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }
}

/// Paths drawn straight onto the page, outside <defs>, as (whole tag, d).
func drawnPaths(_ svg: String) -> [(tag: String, d: String)] {
    let body = svg.components(separatedBy: "</defs>").last ?? svg
    return matches(#"\n(<path [^>]*?\bd="([^"]+)"[^>]*/>)"#, in: body).map { ($0[1], $0[2]) }
}

func number(_ value: Double) -> String {
    let s = String(format: "%.3f", value)
    return s.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
}

/// pdftocairo's path data (absolute M, L, C and Z only) as a CGPath.
func cgPath(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var tokens = d.split(separator: " ").makeIterator()
    func point() -> CGPoint {
        guard let x = tokens.next().flatMap({ Double($0) }), let y = tokens.next().flatMap({ Double($0) })
        else { fail("unreadable path data: \(d.prefix(60))") }
        return CGPoint(x: x, y: y)
    }
    while let op = tokens.next() {
        switch op {
        case "M": path.move(to: point())
        case "L": path.addLine(to: point())
        case "C": let c1 = point(), c2 = point(); path.addCurve(to: point(), control1: c1, control2: c2)
        case "Z": path.closeSubpath()
        default: fail("path command \(op) in pdftocairo output")
        }
    }
    return path
}

/// A CGPath as SVG path data.
func svgPathData(_ path: CGPath) -> String {
    var parts: [String] = []
    func p(_ pt: CGPoint) -> String { "\(number(pt.x)) \(number(pt.y))" }
    path.applyWithBlock { element in
        let pts = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: parts.append("M \(p(pts[0]))")
        case .addLineToPoint: parts.append("L \(p(pts[0]))")
        case .addQuadCurveToPoint: parts.append("Q \(p(pts[0])) \(p(pts[1]))")
        case .addCurveToPoint: parts.append("C \(p(pts[0])) \(p(pts[1])) \(p(pts[2]))")
        case .closeSubpath: parts.append("Z")
        @unknown default: fail("unknown CGPath element")
        }
    }
    return parts.joined(separator: " ")
}

/// `base` with `cut` removed, as one path. The cut is real geometry rather
/// than an SVG <mask>: WebKit draws a <mask> inside an SVG used as an image at
/// the SVG's own pixel size, so a masked icon comes out blurry on Retina.
func cutOut(_ cut: CGPath, from base: CGPath) -> String {
    svgPathData(base.subtracting(cut, using: .winding))
}

// Every file is built before any is written, so a failure leaves the old icons in place.
var files: [(name: String, svg: String)] = []
for (id, name, kind) in symbols {
    let pdf = work.appendingPathComponent("\(id).pdf"), raw = work.appendingPathComponent("\(id).svg")
    MainActor.assumeIsolated { renderPDF(name, kind: kind, to: pdf) }
    convert(pdf, to: raw)
    let svg = try String(contentsOf: raw, encoding: .utf8)
    guard let box = matches(#"viewBox="0 0 ([\d.]+) ([\d.]+)""#, in: svg).first,
          let width = Double(box[1]), let height = Double(box[2])
    else { fail("no viewBox in pdftocairo output for \(name)") }

    let shapes = drawnPaths(svg)
    var body: [String] = []
    switch kind {
    case .cutout:
        let glyph = shapes.filter { $0.tag.contains(glyphFill) }.map(\.d)
        let base = shapes.filter { $0.tag.contains(baseFill) }.map(\.d)
        guard !svg.contains("<image"), !glyph.isEmpty, !base.isEmpty, glyph.count + base.count == shapes.count
        else { fail("\(name) did not come out as a separate glyph and base in palette mode") }
        let cut = cutOut(cgPath(glyph.joined(separator: " ")), from: cgPath(base.joined(separator: " ")))
        body.append(#"<path d="\#(cut)"/>"#)
    case .plain:
        if svg.contains("<image") {
            // The base layer is the second clip path; the bitmap mask is the gap, rebuilt below as a cut.
            let clips = matches(#"<clipPath id="clip-\d+">\s*<path [^>]*?\bd="([^"]+)""#, in: svg).map { $0[1] }
            guard clips.count == 2, svg.components(separatedBy: "<image").count == 2, !shapes.isEmpty,
                  svg.contains(#"<g mask="url(#mask-0)">"#)
            else { fail("\(name) has a bitmap in a shape this script does not know how to rebuild") }
            let arrow = cgPath(shapes.map(\.d).joined(separator: " "))
            let grown = arrow.copy(strokingWithWidth: clearance * 2, lineCap: .butt, lineJoin: .round, miterLimit: 10)
                .union(arrow, using: .winding)
            body.append(#"<path d="\#(cutOut(grown, from: cgPath(clips[1])))"/>"#)
        } else if shapes.isEmpty {
            fail("\(name) produced no paths")
        }
        body += shapes.map { #"<path d="\#($0.d)"/>"# }
    }

    let out = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(number(width)) \(number(height))" width="\(number(width))" height="\(number(height))">
    <!-- \(name). SF Symbols, Apple Inc. Generated by Scripts/export-symbol-icons.swift; do not edit by hand. -->
    \(body.joined(separator: "\n"))
    </svg>

    """
    files.append(("\(id).svg", out))
}
for file in files {
    try file.svg.write(to: outputDir.appendingPathComponent(file.name), atomically: true, encoding: .utf8)
}
print("wrote \(symbols.count) icons to \(outputDir.path)")
