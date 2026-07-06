import Foundation
import Testing
@testable import QuillKit

@Suite struct MimeTypeTests {

    @Test func jpegExtension() {
        #expect(MimeType.forExtension("jpg") == "image/jpeg")
        #expect(MimeType.forExtension("jpeg") == "image/jpeg")
    }

    @Test func pngExtension() {
        #expect(MimeType.forExtension("png") == "image/png")
    }

    @Test func gifExtension() {
        #expect(MimeType.forExtension("gif") == "image/gif")
    }

    @Test func webpExtension() {
        #expect(MimeType.forExtension("webp") == "image/webp")
    }

    @Test func pdfExtension() {
        #expect(MimeType.forExtension("pdf") == "application/pdf")
    }

    @Test func heicExtension() {
        #expect(MimeType.forExtension("heic") == "image/heic")
    }

    @Test func tiffExtension() {
        #expect(MimeType.forExtension("tiff") == "image/tiff")
        #expect(MimeType.forExtension("tif") == "image/tiff")
    }

    @Test func extensionIsCaseInsensitive() {
        #expect(MimeType.forExtension("JPG") == "image/jpeg")
        #expect(MimeType.forExtension("PNG") == "image/png")
    }

    @Test func unknownExtensionFallsBackToOctetStream() {
        #expect(MimeType.forExtension("notarealextension") == "application/octet-stream")
    }

    @Test func emptyExtensionFallsBackToOctetStream() {
        #expect(MimeType.forExtension("") == "application/octet-stream")
    }

    @Test func forFileUsesURLPathExtension() {
        let url = URL(fileURLWithPath: "/tmp/photo.png")
        #expect(MimeType.forFile(url) == "image/png")
    }

    @Test func forFileWithNoExtensionFallsBackToOctetStream() {
        let url = URL(fileURLWithPath: "/tmp/no-extension-file")
        #expect(MimeType.forFile(url) == "application/octet-stream")
    }
}
