import Foundation
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

    @Test func matchesAcceptsOnlyWhatTheServerFilterWouldReturn() {
        let image = media(type: "image")
        #expect(MediaFilter.all.matches(image))
        #expect(MediaFilter.all.matches(media(type: "text")))
        #expect(MediaFilter.images.matches(image))
        #expect(MediaFilter.video.matches(image) == false)
        #expect(MediaFilter.documents.matches(media(type: "application")))
        #expect(MediaFilter.documents.matches(media(type: "text")) == false)
    }

    private func media(type: String) -> WPMedia {
        let json = #"{"id":1,"media_type":"\#(type)"}"#
        return try! JSONDecoder().decode(WPMedia.self, from: Data(json.utf8))
    }

    @Test func everyFilterHasATitleAndAnIcon() {
        for filter in MediaFilter.allCases {
            #expect(filter.title.isEmpty == false)
            #expect(filter.icon.isEmpty == false)
        }
    }
}
