// Pixel-precise scrolling for framing a screenshot, which the computer-use scroll (about 38pt a
// notch) can't do. Scrolls whatever is under (x, y), in screen points, by dy points: positive moves
// the content up (like scrolling down). Refuses unless the window under the point is Quill's.
// Build: swiftc -O scroll.swift -o "$S/scroll"   Run: "$S/scroll" 700 500 12
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 4, let x = Double(args[1]), let y = Double(args[2]), let dy = Int32(args[3]) else {
    FileHandle.standardError.write("usage: scroll <x> <y> <dy>\n".data(using: .utf8)!)
    exit(2)
}
let point = CGPoint(x: x, y: y)
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let front = windows.first { window in
    guard (window[kCGWindowLayer as String] as? Int) == 0,
          let b = window[kCGWindowBounds as String] as? [String: Double] else { return false }
    return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0).contains(point)
}
guard (front?[kCGWindowOwnerName as String] as? String) == "Quill" else {
    FileHandle.standardError.write("The window under (\(x), \(y)) isn't Quill's; nothing scrolled.\n".data(using: .utf8)!)
    exit(1)
}
CGWarpMouseCursorPosition(point)
usleep(50_000)
// Several small steps, so WebKit and AppKit don't treat it as a fling.
var left = dy
while left != 0 {
    let step = left > 0 ? min(left, 8) : max(left, -8)
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0)
    event?.location = point
    event?.post(tap: .cghidEventTap)
    left -= step
    usleep(15_000)
}
