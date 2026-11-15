// Prints "<window id> <x> <y> <width> <height>" (points) for each on-screen, normal-level window of an app.
// Build once: swiftc -O winid.swift -o "$SCRATCH/winid"   Run: "$SCRATCH/winid" Quill
import CoreGraphics

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Quill"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerName as String] as? String) == owner
    && (window[kCGWindowLayer as String] as? Int) == 0 {
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let id = window[kCGWindowNumber as String] ?? 0
    print(id, bounds["X"] ?? 0, bounds["Y"] ?? 0, bounds["Width"] ?? 0, bounds["Height"] ?? 0)
}
