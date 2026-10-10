import AppKit
import AVFoundation
import WebKit

final class FileSchemeHandler: NSObject, WKURLSchemeHandler {
    let root: URL
    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let file = root.appendingPathComponent(url.path.removingPercentEncoding ?? url.path)
        guard file.standardizedFileURL.path.hasPrefix(root.path), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let types = ["html": "text/html", "js": "text/javascript", "css": "text/css", "svg": "image/svg+xml", "woff2": "font/woff2", "png": "image/png"]
        let mime = types[file.pathExtension] ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text") ? "utf-8" : nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

@MainActor
final class Renderer: NSObject, WKNavigationDelegate {
    let options: Options
    let webView: WKWebView
    let window: NSWindow
    var loaded: CheckedContinuation<Void, Never>?

    init(options: Options) {
        self.options = options
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(FileSchemeHandler(root: options.root), forURLScheme: "quill-video")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: config)
        webView.appearance = NSAppearance(named: .aqua)
        window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: width, height: height), styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        webView.navigationDelegate = self
        window.contentView = webView
        window.orderFrontRegardless()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func load() async {
        await withCheckedContinuation { cont in
            loaded = cont
            webView.load(URLRequest(url: URL(string: "quill-video://app/video/index.html")!))
        }
    }

    func seek(_ t: Double) async throws {
        _ = try await webView.callAsyncJavaScript("await window.seek(t); return true", arguments: ["t": t], contentWorld: .page)
    }

    func snapshot() async throws -> CGImage {
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: width, height: height)
        config.afterScreenUpdates = true
        let image = try await webView.takeSnapshot(configuration: config)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw URLError(.cannotDecodeContentData) }
        return cg
    }

    func draw(_ image: CGImage, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func writeStills() async throws {
        let dir = options.stillsDir ?? options.output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for t in options.stills {
            try await seek(t)
            let image = try await snapshot()
            let rep = NSBitmapImageRep(cgImage: image)
            let file = dir.appendingPathComponent(String(format: "t%05.2f.png", t))
            try rep.representation(using: .png, properties: [:])?.write(to: file)
            print("still \(file.lastPathComponent)")
        }
    }

    func writeVideo() async throws {
        try? FileManager.default.removeItem(at: options.output)
        let writer = try AVAssetWriter(outputURL: options.output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: options.bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: options.fps * 2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let duration = try await webView.callAsyncJavaScript("return window.DURATION", contentWorld: .page) as? Double ?? 60
        let frames = Int(duration * Double(options.fps))
        let started = Date()
        for frame in 0..<frames {
            try await seek(Double(frame) / Double(options.fps))
            let image = try await snapshot()
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { throw URLError(.cannotCreateFile) }
            draw(image, into: buffer)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(options.fps)))
            if frame % options.fps == 0 {
                print(String(format: "%5.1fs / %.0fs  (%.0fs elapsed)", Double(frame) / Double(options.fps), duration, Date().timeIntervalSince(started)))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        print("wrote \(options.output.path)")
    }

    func writeAudio(muxing video: URL) async throws {
        let raw = try await webView.callAsyncJavaScript("return window.audioCues()", contentWorld: .page) as? [[String: Any]] ?? []
        let cues = raw.compactMap { d -> Cue? in
            guard let t = d["t"] as? Double, let kind = d["kind"] as? String else { return nil }
            return Cue(t: t, kind: kind)
        }
        let duration = try await webView.callAsyncJavaScript("return window.DURATION", contentWorld: .page) as? Double ?? 60
        var mix = AudioMix(duration: duration)
        mix.addEffects(cues, gain: options.effectsGain)
        if let music = options.music { try mix.addMusic(from: music, gain: options.musicGain) }
        mix.normalize()
        let audio = options.output.deletingPathExtension().appendingPathExtension("m4a")
        try mix.write(to: audio)
        try await mux(video: video, audio: audio, into: options.output)
        print("wrote \(options.output.path) with \(cues.count) cues\(options.music.map { " and \($0.lastPathComponent)" } ?? "")")
    }

    func run() async throws {
        await load()
        if let video = options.mux {
            try await writeAudio(muxing: video)
        } else if options.stills.isEmpty {
            try await writeVideo()
        } else {
            try await writeStills()
        }
    }
}
