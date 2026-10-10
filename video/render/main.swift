// Usage: render <repo-root> <output.mp4> [--fps 60] [--bitrate n] [--stills t,t --stills-dir dir] [--mux silent.mp4 --music file --music-gain 0.55]
import AppKit
import AVFoundation
import WebKit

let width = 1920
let height = 1080

struct Options {
    var root: URL
    var output: URL
    var fps = 60
    var bitrate = 1_200_000
    var stills: [Double] = []
    var stillsDir: URL?
    var mux: URL?
    var music: URL?
    var musicGain: Float = 0.55
    var effectsGain: Float = 1

    init() {
        var args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 2 else {
            FileHandle.standardError.write("usage: render <repo-root> <output.mp4> [--fps n] [--bitrate n] [--stills t,t --stills-dir dir] [--mux silent.mp4 --music file]\n".data(using: .utf8)!)
            exit(2)
        }
        root = URL(fileURLWithPath: args.removeFirst()).standardizedFileURL
        output = URL(fileURLWithPath: args.removeFirst())
        while !args.isEmpty {
            let flag = args.removeFirst()
            let value = args.isEmpty ? "" : args.removeFirst()
            switch flag {
            case "--fps": fps = Int(value) ?? fps
            case "--bitrate": bitrate = Int(value) ?? bitrate
            case "--stills": stills = value.split(separator: ",").compactMap { Double($0) }
            case "--stills-dir": stillsDir = URL(fileURLWithPath: value)
            case "--mux": mux = URL(fileURLWithPath: value)
            case "--music": music = URL(fileURLWithPath: value)
            case "--music-gain": musicGain = Float(value) ?? musicGain
            case "--effects-gain": effectsGain = Float(value) ?? effectsGain
            default: break
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    let renderer = Renderer(options: Options())
    do {
        try await renderer.run()
        exit(0)
    } catch {
        FileHandle.standardError.write("render failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
app.run()
