import Testing
@testable import QuillKit

@Suite struct MediaFilterTests {
    @Test func allSendsNoMediaTypeParameter() {
        #expect(MediaFilter.all.mediaTypeParameter == nil)
    }

    @Test func eachFilterMapsToItsWordPressMediaType() {
        #expect(MediaFilter.images.mediaTypeParameter == "image")
        #expect(MediaFilter.documents.mediaTypeParameter == "application")
        #expect(MediaFilter.audio.mediaTypeParameter == "audio")
        #expect(MediaFilter.video.mediaTypeParameter == "video")
    }

    @Test func everyFilterHasATitleAndAnIcon() {
        for filter in MediaFilter.allCases {
            #expect(filter.title.isEmpty == false)
            #expect(filter.icon.isEmpty == false)
        }
    }
}
