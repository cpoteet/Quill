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
        let image = media(type: "image", mime: "image/png")
        let docx = media(type: "file", mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
        let text = media(type: "file", mime: "text/plain")
        #expect(MediaFilter.all.matches(text))
        #expect(MediaFilter.images.matches(image))
        #expect(MediaFilter.video.matches(image) == false)
        #expect(MediaFilter.documents.matches(docx))
        #expect(MediaFilter.documents.matches(text) == false)
        #expect(MediaFilter.audio.matches(media(type: "file", mime: "audio/mpeg")))
        #expect(MediaFilter.video.matches(media(type: "file", mime: "video/mp4")))
    }

    private func media(type: String, mime: String) -> WPMedia {
        let json = #"{"id":1,"media_type":"\#(type)","mime_type":"\#(mime)"}"#
        return try! JSONDecoder().decode(WPMedia.self, from: Data(json.utf8))
    }

    @Test func everyFilterHasATitleAndAnIcon() {
        for filter in MediaFilter.allCases {
            #expect(filter.title.isEmpty == false)
            #expect(filter.icon.isEmpty == false)
        }
    }
}
