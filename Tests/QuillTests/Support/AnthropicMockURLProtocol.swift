import Foundation

/// Separate URLProtocol stub for AnthropicClientTests. Uses its own static handler so it
/// doesn't conflict with MockURLProtocol used by WordPressClientTests — the two @Suite(.serialized)
/// suites run concurrently with each other even though each is internally serialized.
final class AnthropicMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = AnthropicMockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            // URLSession clears httpBody and uses httpBodyStream in URLProtocol.
            // Reconstruct httpBody so handlers can inspect the request body normally.
            var req = request
            if req.httpBody == nil, let stream = req.httpBodyStream {
                stream.open()
                var body = Data()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buf.deallocate(); stream.close() }
                while stream.hasBytesAvailable {
                    let n = stream.read(buf, maxLength: 4096)
                    if n > 0 { body.append(buf, count: n) }
                }
                req.httpBody = body
            }
            let (response, data) = try handler(req)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
