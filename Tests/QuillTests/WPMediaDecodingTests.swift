import Foundation
import Testing
@testable import QuillKit

@Suite struct WPMediaDecodingTests {

    private func decode(_ json: String) throws -> WPMedia {
        try JSONDecoder().decode(WPMedia.self, from: json.data(using: .utf8)!)
    }

    @Test func integerDimensionsDecode() throws {
        let json = """
        {"id":1,"title":{"rendered":"photo.jpg"},"source_url":"https://example.com/photo.jpg",
         "media_type":"image","mime_type":"image/jpeg","link":"https://example.com/?p=1","date":"2024-01-01T00:00:00",
         "media_details":{"width":2560,"height":1440}}
        """
        let media = try decode(json)
        #expect(media.mediaDetails?.width == 2560)
        #expect(media.mediaDetails?.height == 1440)
    }

    // The documented float-dimensions gotcha: WordPress returns 2560.0 on some installs
    @Test func floatDimensionsDecodeToInt() throws {
        let json = """
        {"id":2,"source_url":"https://example.com/img.jpg",
         "media_details":{"width":2560.0,"height":1440.0}}
        """
        let media = try decode(json)
        #expect(media.mediaDetails?.width == 2560)
        #expect(media.mediaDetails?.height == 1440)
    }

    @Test func missingMediaDetailsIsNil() throws {
        let json = """
        {"id":3,"source_url":"https://example.com/doc.pdf",
         "media_type":"file","mime_type":"application/pdf"}
        """
        let media = try decode(json)
        #expect(media.mediaDetails == nil)
    }

    @Test func missingTitleDefaultsToEmpty() throws {
        let json = """
        {"id":4,"source_url":"https://example.com/img.jpg"}
        """
        let media = try decode(json)
        #expect(media.title.rendered == "")
    }

    @Test func sizesMapDecodes() throws {
        let json = """
        {"id":5,"source_url":"https://example.com/img.jpg",
         "media_details":{
           "width":2560,"height":1440,
           "sizes":{
             "thumbnail":{"source_url":"https://example.com/img-150x150.jpg","width":150,"height":150},
             "medium":{"source_url":"https://example.com/img-300x200.jpg","width":300,"height":200}
           }
         }}
        """
        let media = try decode(json)
        #expect(media.mediaDetails?.sizes?["thumbnail"]?.width == 150)
        #expect(media.mediaDetails?.sizes?["medium"]?.height == 200)
        #expect(media.mediaDetails?.sizes?["thumbnail"]?.sourceURL == "https://example.com/img-150x150.jpg")
    }

    // Sizes map with float dimensions
    @Test func sizesDimensionsAsFloatsDecode() throws {
        let json = """
        {"id":6,"source_url":"https://example.com/img.jpg",
         "media_details":{
           "sizes":{"full":{"source_url":"https://example.com/img.jpg","width":2560.0,"height":1440.0}}
         }}
        """
        let media = try decode(json)
        #expect(media.mediaDetails?.sizes?["full"]?.width == 2560)
        #expect(media.mediaDetails?.sizes?["full"]?.height == 1440)
    }

    // Malformed sizes (wrong type) — should swallow to nil, not crash
    @Test func malformedSizesDoesNotCrash() throws {
        let json = """
        {"id":7,"source_url":"https://example.com/img.jpg",
         "media_details":{"width":100,"height":100,"sizes":[]}}
        """
        let media = try decode(json)
        #expect(media.id == 7)
        #expect(media.mediaDetails?.sizes == nil)
    }

    @Test func altTextDecodesFromAltText() throws {
        let json = """
        {"id":8,"source_url":"https://example.com/img.jpg","alt_text":"A sunset photo"}
        """
        let media = try decode(json)
        #expect(media.altText == "A sunset photo")
    }

    @Test func missingAltTextDefaultsToEmpty() throws {
        let json = """
        {"id":9,"source_url":"https://example.com/img.jpg"}
        """
        let media = try decode(json)
        #expect(media.altText == "")
    }

    @Test func thumbnailURLUsesThumbnailSizeWhenPresent() throws {
        let json = """
        {"id":10,"source_url":"https://example.com/img.jpg",
         "media_details":{
           "sizes":{
             "thumbnail":{"source_url":"https://example.com/img-150x150.jpg","width":150,"height":150}
           }
         }}
        """
        let media = try decode(json)
        #expect(media.thumbnailURL == "https://example.com/img-150x150.jpg")
    }

    @Test func thumbnailURLFallsBackToSourceURLWhenNoThumbnailSize() throws {
        let json = """
        {"id":11,"source_url":"https://example.com/img.jpg"}
        """
        let media = try decode(json)
        #expect(media.thumbnailURL == "https://example.com/img.jpg")
    }

    @Test func sizedURLUsesMatchingSizeWhenPresent() throws {
        let json = """
        {"id":12,"source_url":"https://example.com/img.jpg",
         "media_details":{
           "sizes":{
             "medium":{"source_url":"https://example.com/img-300x300.jpg","width":300,"height":300}
           }
         }}
        """
        let media = try decode(json)
        #expect(media.sizedURL(for: "medium") == "https://example.com/img-300x300.jpg")
    }

    @Test func sizedURLFallsBackToSourceURLWhenSizeMissing() throws {
        let json = """
        {"id":13,"source_url":"https://example.com/img.jpg"}
        """
        let media = try decode(json)
        #expect(media.sizedURL(for: "large") == "https://example.com/img.jpg")
    }

    @Test func sizedURLFallsBackToSourceURLWhenMatchedSizeHasBlankURL() throws {
        let json = """
        {"id":14,"source_url":"https://example.com/img.jpg",
         "media_details":{
           "sizes":{
             "large":{"source_url":"","width":1024,"height":768}
           }
         }}
        """
        let media = try decode(json)
        #expect(media.sizedURL(for: "large") == "https://example.com/img.jpg")
    }

    @Test func sizedURLAlwaysUsesSourceURLForFullSlugEvenWhenAFullSizeEntryExists() throws {
        let json = """
        {"id":15,"source_url":"https://example.com/img.jpg",
         "media_details":{
           "sizes":{
             "full":{"source_url":"https://example.com/img-full-variant.jpg","width":2000,"height":1500}
           }
         }}
        """
        let media = try decode(json)
        #expect(media.sizedURL(for: "full") == "https://example.com/img.jpg")
    }
}
