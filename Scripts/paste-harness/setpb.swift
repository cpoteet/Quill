import AppKit

// Puts an HTML file (and optional plain-text file) on the system pasteboard; see "Running the manual pass with an agent" in docs/testing-plan.md.

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: setpb <html-file> [text-file]")
    exit(1)
}
let html = try! String(contentsOfFile: args[1], encoding: .utf8)
let text = args.count > 2 ? try! String(contentsOfFile: args[2], encoding: .utf8) : html
let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString(html, forType: .html)
pasteboard.setString(text, forType: .string)
