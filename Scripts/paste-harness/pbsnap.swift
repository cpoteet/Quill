import AppKit
// Saves or restores every flavor on the general pasteboard: pbsnap save|load <dir>
let pb = NSPasteboard.general
let mode = CommandLine.arguments[1], dir = URL(fileURLWithPath: CommandLine.arguments[2])
let fm = FileManager.default
if mode == "save" {
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    var order: [String] = []
    for t in pb.types ?? [] {
        guard let d = pb.data(forType: t) else { continue }
        let name = String(order.count)
        try! d.write(to: dir.appendingPathComponent(name))
        order.append(t.rawValue)
    }
    try! JSONSerialization.data(withJSONObject: order).write(to: dir.appendingPathComponent("types.json"))
    print("saved \(order.count) flavors")
} else {
    let order = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("types.json"))) as! [String]
    pb.clearContents()
    pb.declareTypes(order.map { NSPasteboard.PasteboardType($0) }, owner: nil)
    for (i, t) in order.enumerated() {
        let d = try! Data(contentsOf: dir.appendingPathComponent(String(i)))
        pb.setData(d, forType: NSPasteboard.PasteboardType(t))
    }
    print("loaded \(order.count) flavors")
}
