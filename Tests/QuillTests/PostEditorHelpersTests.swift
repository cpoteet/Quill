import Foundation
import Testing
@testable import QuillKit

@Suite struct PostEditorHelpersTests {

    // MARK: - previewURL (Issue 2)

    @Test func previewURLRefusesANonWebScheme() {
        #expect(PostEditorView.previewURL(from: "file:///etc/passwd") == nil)
        #expect(PostEditorView.previewURL(from: "javascript:alert(1)") == nil)
    }

    @Test func previewURLAppendsFreshQueryToCleanURL() {
        let url = PostEditorView.previewURL(from: "https://example.com/my-post/")
        #expect(url?.query == "preview=true")
    }

    @Test func previewURLAppendsPreviewAlongsideExistingQuery() {
        let url = PostEditorView.previewURL(from: "https://example.com/?p=123")
        #expect(url?.query?.contains("p=123") == true)
        #expect(url?.query?.contains("preview=true") == true)
        #expect(url?.absoluteString.contains("?p=123?") == false)
    }

    @Test func previewURLReplacesExistingPreviewFalseParam() {
        let url = PostEditorView.previewURL(from: "https://example.com/post/?preview=false")
        #expect(url?.query == "preview=true")
    }

    @Test func previewURLPreservesMultipleExistingParams() {
        let url = PostEditorView.previewURL(from: "https://example.com/?p=123&foo=bar")
        #expect(url?.query?.contains("foo=bar") == true)
        #expect(url?.query?.contains("preview=true") == true)
    }

    @Test func previewURLPreservesFragment() {
        let url = PostEditorView.previewURL(from: "https://example.com/my-post/#section")
        #expect(url?.fragment == "section")
        #expect(url?.query == "preview=true")
    }

    // MARK: - Autosave restore baseline

    private func serverPost(title: String = "Hello", content: String = "<p>Server</p>", modified: String) throws -> WPPost {
        let json = """
        {"id":7,"title":{"rendered":"\(title)"},"content":{"rendered":"\(content)"},
         "status":"draft","date":"2026-01-01T00:00:00","modified":"\(modified)",
         "slug":"hello","link":"https://example.com/hello"}
        """
        return try JSONDecoder().decode(WPPost.self, from: Data(json.utf8))
    }

    private func snapshot(title: String = "Hello", content: String = "<p>Local</p>", serverModified: String) -> AutosaveSnapshot {
        AutosaveSnapshot(postID: 7, title: title, content: content, footnotes: "", savedAt: Date(), serverModified: serverModified)
    }

    @Test func autosaveOnUnchangedServerKeepsTheServerBaseline() throws {
        let post = try serverPost(modified: "2026-09-01T10:00:00")
        let baseline = PostEditorView.autosaveRestoreBaseline(snapshot(serverModified: "2026-09-01T10:00:00"), over: post)
        #expect(baseline == post.modified)
    }

    @Test func autosaveOnChangedServerKeepsItsOwnBaseline() throws {
        let post = try serverPost(modified: "2026-09-02T12:00:00")
        let baseline = PostEditorView.autosaveRestoreBaseline(snapshot(serverModified: "2026-09-01T10:00:00"), over: post)
        #expect(baseline == "2026-09-01T10:00:00")
        #expect(baseline != post.modified)
    }

    @Test func autosaveWithBlankTimestampNeverMatchesTheServer() throws {
        let post = try serverPost(modified: "2026-09-01T10:00:00")
        let baseline = PostEditorView.autosaveRestoreBaseline(snapshot(serverModified: ""), over: post)
        #expect(baseline == "")
        #expect(baseline != post.modified)
    }

    @Test func emptyAutosaveWithUnchangedTitleIsDiscarded() throws {
        let post = try serverPost(modified: "2026-09-01T10:00:00")
        let baseline = PostEditorView.autosaveRestoreBaseline(snapshot(content: "  ", serverModified: "2026-09-01T10:00:00"), over: post)
        #expect(baseline == nil)
    }

    // MARK: - Stash after a save that finished on another post

    @Test func stashMatchingTheSaveIsDeleted() {
        #expect(PostEditorView.stashAfterSave(snapshot(serverModified: "old"), title: "Hello", content: "<p>Local</p>",
                                              footnotes: "", serverModified: "new") == nil)
        #expect(PostEditorView.stashAfterSave(nil, title: "Hello", content: "<p>Local</p>", footnotes: "", serverModified: "new") == nil)
    }

    @Test func stashWithLaterEditsIsKeptOnTheSavedVersion() {
        let kept = PostEditorView.stashAfterSave(snapshot(content: "<p>Later</p>", serverModified: "old"), title: "Hello",
                                                 content: "<p>Local</p>", footnotes: "", serverModified: "new")
        #expect(kept?.content == "<p>Later</p>")
        #expect(kept?.serverModified == "new")
    }

    @Test func stashDifferingOnlyInFootnotesIsKept() {
        let kept = PostEditorView.stashAfterSave(snapshot(serverModified: "old"), title: "Hello", content: "<p>Local</p>",
                                                 footnotes: #"[{"id":"a","content":"Note"}]"#, serverModified: "new")
        #expect(kept?.footnotes == "")
        #expect(kept?.serverModified == "new")
    }

    // MARK: - Preview conflict check

    @Test func previewOverwritesOnlyADraft() {
        #expect(PostEditorView.previewOverwritesPost(status: "draft"))
        for status in ["pending", "publish", "future", "private"] {
            #expect(!PostEditorView.previewOverwritesPost(status: status))
        }
    }

    // MARK: - Status helpers

    @Test func publishButtonTitlePerStatus() {
        #expect(PostEditorView.publishButtonTitle(status: .draft, isLocal: true, isPublishedRemote: false) == "Save to WordPress")
        #expect(PostEditorView.publishButtonTitle(status: .draft, isLocal: false, isPublishedRemote: false) == "Save Draft")
        #expect(PostEditorView.publishButtonTitle(status: .draft, isLocal: false, isPublishedRemote: true) == "Switch to Draft")
        #expect(PostEditorView.publishButtonTitle(status: .future, isLocal: false, isPublishedRemote: false) == "Schedule")
        #expect(PostEditorView.publishButtonTitle(status: .pending, isLocal: false, isPublishedRemote: false) == "Submit for Review")
        #expect(PostEditorView.publishButtonTitle(status: .private, isLocal: false, isPublishedRemote: false) == "Publish Privately")
        #expect(PostEditorView.publishButtonTitle(status: .publish, isLocal: true, isPublishedRemote: false) == "Publish")
        #expect(PostEditorView.publishButtonTitle(status: .publish, isLocal: false, isPublishedRemote: true) == "Update")
    }

    @Test func publishButtonIconPerStatus() {
        #expect(PostEditorView.publishButtonIcon(status: .draft, isPublishedRemote: false) == "icloud.and.arrow.up")
        #expect(PostEditorView.publishButtonIcon(status: .draft, isPublishedRemote: true) == "icloud.and.arrow.up")
        #expect(PostEditorView.publishButtonIcon(status: .publish, isPublishedRemote: true) == "arrow.up.circle")
        for status in [PostStatus.publish, .future, .pending, .private] {
            #expect(PostEditorView.publishButtonIcon(status: status, isPublishedRemote: false) == "paperplane")
        }
        for status in [PostStatus.future, .pending, .private] {
            #expect(PostEditorView.publishButtonIcon(status: status, isPublishedRemote: true) == "paperplane")
        }
    }

    @Test func toastMessagePerStatus() {
        #expect(PostEditorView.toastMessage(forStatus: .publish) == "Published")
        #expect(PostEditorView.toastMessage(forStatus: .future) == "Scheduled")
        #expect(PostEditorView.toastMessage(forStatus: .pending) == "Submitted for review")
        #expect(PostEditorView.toastMessage(forStatus: .private) == "Published privately")
        #expect(PostEditorView.toastMessage(forStatus: .draft) == "Draft saved")
    }

    // MARK: - Dropped-image upload feedback

    @Test func pastedImageFileExtensionFollowsTheBytesNotTheLabel() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(PostEditorView.fileExtension(for: jpeg, mimeType: "image/png") == "jpg")
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
        #expect(PostEditorView.fileExtension(for: png, mimeType: "image/jpeg") == "png")
        let webp = Data("RIFF\0\0\0\0WEBP".utf8)
        #expect(PostEditorView.fileExtension(for: webp, mimeType: "image/png") == "webp")
        let heic = Data([0, 0, 0, 0x18] + Array("ftypheic".utf8))
        #expect(PostEditorView.fileExtension(for: heic, mimeType: "image/png") == "heic")
        let gif = Data("GIF89a\0\0\0\0\0\0".utf8)
        #expect(PostEditorView.fileExtension(for: gif, mimeType: "image/png") == "gif")
    }

    @Test func pastedImageFileExtensionFallsBackToItsType() {
        let unknown = Data([1, 2, 3])
        #expect(PostEditorView.fileExtension(for: unknown, mimeType: "image/gif") == "gif")
        #expect(PostEditorView.fileExtension(for: unknown, mimeType: "image/x-unknown") == "png")
    }

    @Test func uploadStatusTextForSingleFile() {
        #expect(PostEditorView.uploadStatusText(index: 1, total: 1) == "Uploading image…")
    }

    @Test func uploadStatusTextForMultipleFiles() {
        #expect(PostEditorView.uploadStatusText(index: 1, total: 3) == "Uploading image 1 of 3…")
        #expect(PostEditorView.uploadStatusText(index: 2, total: 3) == "Uploading image 2 of 3…")
        #expect(PostEditorView.uploadStatusText(index: 3, total: 3) == "Uploading image 3 of 3…")
    }

    @Test func uploadSuccessMessageForSingleFile() {
        #expect(PostEditorView.uploadSuccessMessage(inserted: 1, didConvert: false) == "Image inserted")
        #expect(PostEditorView.uploadSuccessMessage(inserted: 1, didConvert: true) == "Converted to JPEG · Image inserted")
    }

    @Test func uploadSuccessMessageForMultipleFiles() {
        #expect(PostEditorView.uploadSuccessMessage(inserted: 3, didConvert: false) == "3 images inserted")
        #expect(PostEditorView.uploadSuccessMessage(inserted: 3, didConvert: true) == "3 images inserted")
    }

    @Test func uploadFailureMessageForSingleFileKeepsUnderlyingError() {
        #expect(
            PostEditorView.uploadFailureMessage(failed: 1, total: 1, firstError: "The network connection was lost.")
                == "Upload failed: The network connection was lost."
        )
    }

    @Test func uploadFailureMessageForMultipleFilesSummarizes() {
        #expect(
            PostEditorView.uploadFailureMessage(failed: 2, total: 3, firstError: "boom")
                == "2 of 3 images failed to upload"
        )
    }

    @Test func uploadNotInsertedMessageNamesTheMediaLibrary() {
        #expect(PostEditorView.uploadNotInsertedMessage(count: 1)
                == "Image uploaded to the Media Library but not inserted, because a different post is open")
        #expect(PostEditorView.uploadNotInsertedMessage(count: 2)
                == "2 images uploaded to the Media Library but not inserted, because a different post is open")
    }

    @Test func uploadSuccessMessageForTwoFilesUsesThePluralForm() {
        #expect(PostEditorView.uploadSuccessMessage(inserted: 2, didConvert: false) == "2 images inserted")
    }

    // handleDroppedImages never reaches this: an all-failed drop routes to the
    // failure branch, and an empty drop returns before any message is built.
    // Pinned so the plural fallthrough stays sane if the guard is ever relaxed.
    @Test func uploadSuccessMessageWithNothingInsertedFallsThroughToPlural() {
        #expect(PostEditorView.uploadSuccessMessage(inserted: 0, didConvert: false) == "0 images inserted")
        #expect(PostEditorView.uploadSuccessMessage(inserted: 0, didConvert: true) == "0 images inserted")
    }

    @Test func uploadFailureMessageWhenEveryFileInAMultiDropFails() {
        #expect(
            PostEditorView.uploadFailureMessage(failed: 3, total: 3, firstError: "boom")
                == "3 of 3 images failed to upload"
        )
    }

    // A partial multi-file failure deliberately drops the underlying error text:
    // the count is the useful signal, and only the first error was captured.
    @Test func uploadFailureMessageForPartialMultiDropOmitsTheErrorText() {
        let msg = PostEditorView.uploadFailureMessage(failed: 1, total: 2, firstError: "The network connection was lost.")
        #expect(msg == "1 of 2 images failed to upload")
        #expect(msg.contains("network") == false)
    }

    @Test func statusChangeToFutureSetsDefaultDate() {
        var s = PostSettings()
        s.status = .future
        s.statusDidChange()
        #expect(s.publishDate != nil)
    }

    @Test func statusChangeToPrivateClearsScheduledDate() {
        var s = PostSettings()
        s.status = .future
        s.statusDidChange()
        s.status = .private
        s.statusDidChange()
        #expect(s.publishDate == nil)
    }

    @Test func statusChangeToFuturePreservesExistingDate() {
        var s = PostSettings()
        let existing = Date().addingTimeInterval(7200)
        s.status = .future
        s.publishDate = existing
        s.statusDidChange()
        #expect(s.publishDate == existing)
    }

    @Test func statusChangeToPendingClearsScheduledDate() {
        var s = PostSettings()
        s.status = .future
        s.statusDidChange()
        s.status = .pending
        s.statusDidChange()
        #expect(s.publishDate == nil)
    }

    @Test func scheduledDateEarlierTodayHasPassed() {
        var s = PostSettings()
        let now = Date()
        s.publishDate = now.addingTimeInterval(-8 * 3600)
        #expect(s.scheduledDateHasPassed(now: now))
    }

    @Test func scheduledDateUnderAMinuteAwayHasPassed() {
        var s = PostSettings()
        let now = Date()
        s.publishDate = now.addingTimeInterval(30)
        #expect(s.scheduledDateHasPassed(now: now))
    }

    @Test func scheduledDateInTheFutureHasNotPassed() {
        var s = PostSettings()
        let now = Date()
        s.publishDate = now.addingTimeInterval(3600)
        #expect(s.scheduledDateHasPassed(now: now) == false)
    }

    @Test func missingScheduledDateHasNotPassed() {
        #expect(PostSettings().scheduledDateHasPassed() == false)
    }

    @Test func pastScheduledDateIsSentAsPublish() {
        var s = PostSettings()
        let now = Date()
        s.publishDate = now.addingTimeInterval(-3600)
        #expect(PostEditorView.effectiveStatus(.future, settings: s, now: now) == .publish)
    }

    @Test func futureScheduledDateIsSentAsFuture() {
        var s = PostSettings()
        let now = Date()
        s.publishDate = now.addingTimeInterval(3600)
        #expect(PostEditorView.effectiveStatus(.future, settings: s, now: now) == .future)
    }

    @Test func nonScheduledStatusIsSentUnchanged() {
        var s = PostSettings()
        let now = Date()
        s.publishDate = now.addingTimeInterval(-3600)
        #expect(PostEditorView.effectiveStatus(.draft, settings: s, now: now) == .draft)
    }

    // MARK: - Settings from a WordPress post

    private func settingsPost(status: String, dateGmt: String = "2026-10-01T09:30:00") throws -> WPPost {
        let json = """
        {"id":7,"title":{"rendered":"T"},"content":{"rendered":""},"excerpt":{"raw":"Short &amp; sweet","rendered":"<p>Short &amp; sweet</p>"},
         "status":"\(status)","date":"2026-10-01T04:30:00","date_gmt":"\(dateGmt)","modified":"2026-01-01T00:00:00",
         "slug":"the-slug","link":"https://example.com/t","categories":[3,4],"tags":[9],"featured_media":12,
         "comment_status":"closed","parent":2}
        """
        return try JSONDecoder().decode(WPPost.self, from: Data(json.utf8))
    }

    @Test func settingsFromAPostCarryEveryField() throws {
        let s = PostSettings(post: try settingsPost(status: "publish"))
        #expect(s.status == .publish)
        #expect(s.categoryIDs == [3, 4])
        #expect(s.tagIDs == [9])
        #expect(s.featuredMediaID == 12)
        #expect(s.slug == "the-slug")
        #expect(s.commentStatus == "closed")
        #expect(s.parentID == 2)
        #expect(s.excerpt == "Short & sweet")
        #expect(s.publishDate == nil)
        #expect(s.newTagNames.isEmpty && s.newCategoryNames.isEmpty)
    }

    @Test func settingsFromAScheduledPostReadTheGMTDateAsUTC() throws {
        let s = PostSettings(post: try settingsPost(status: "future"))
        #expect(s.publishDate == Date(timeIntervalSince1970: 1_790_847_000))
    }

    @Test func settingsFromAScheduledPostWithoutAGMTDateReadTheLocalDateAsUTC() throws {
        let s = PostSettings(post: try settingsPost(status: "future", dateGmt: ""))
        #expect(s.publishDate == Date(timeIntervalSince1970: 1_790_829_000))
    }

    @Test func settingsFromAScheduledPostAcceptAZoneSuffix() throws {
        let s = PostSettings(post: try settingsPost(status: "future", dateGmt: "2026-10-01T09:30:00Z"))
        #expect(s.publishDate == Date(timeIntervalSince1970: 1_790_847_000))
    }

    @Test func plainExcerptStripsTagsAndOuterWhitespace() {
        #expect(PostEditorView.plainExcerpt("\n <p>Short <em>and</em> sweet</p>\n") == "Short and sweet")
        #expect(PostEditorView.plainExcerpt("No markup") == "No markup")
    }

    // MARK: - PostStats reading time

    @Test func readingTimeZeroWordsIsZero() {
        #expect(PostStats(words: 0, characters: 0).readingMinutes == 0)
    }

    @Test func readingTimeShortTextIsOneMinute() {
        #expect(PostStats(words: 1, characters: 5).readingMinutes == 1)
        #expect(PostStats(words: 238, characters: 1000).readingMinutes == 1)
    }

    @Test func readingTimeRoundsUp() {
        #expect(PostStats(words: 239, characters: 1000).readingMinutes == 2)
        #expect(PostStats(words: 1000, characters: 5000).readingMinutes == 5)  // 1000/238 = 4.2 → 5
    }
}

@Suite struct GalleryEditTests {

    private func media(id: Int, link: String = "https://example.com/?attachment_id=1") throws -> WPMedia {
        let json = """
        {"id":\(id),"title":{"rendered":"p\(id)"},"source_url":"https://example.com/p\(id).jpg",\
        "media_type":"image","mime_type":"image/jpeg","link":"\(link)",\
        "media_details":{"sizes":{"large":{"source_url":"https://example.com/p\(id)-1024x683.jpg","width":1024,"height":683},\
        "thumbnail":{"source_url":"https://example.com/p\(id)-150x150.jpg","width":150,"height":150}}}}
        """
        return try JSONDecoder().decode(WPMedia.self, from: Data(json.utf8))
    }

    private func image(
        id: Int?, url: String, sizeSlug: String? = "large", href: String? = nil,
        caption: String = "", captionHTML: String? = nil, blockAttrs: String? = nil, extraClasses: String = ""
    ) -> GalleryImage {
        GalleryImage(
            id: id, url: url, fullUrl: nil, alt: "", caption: caption, captionHTML: captionHTML,
            sizeSlug: sizeSlug, href: href, blockAttrs: blockAttrs, extraClasses: extraClasses)
    }

    private func edit(_ images: [GalleryImage], linkTo: String = "none") -> GalleryEdit {
        GalleryEdit(images: images, columns: 2, cropped: true, linkTo: linkTo)
    }

    private func images(_ payload: [String: Any]) -> [[String: Any]] {
        payload["images"] as? [[String: Any]] ?? []
    }

    @Test func galleryEditDecodesTheEditBody() {
        let body: [String: Any] = ["edit": [
            "images": [
                ["id": 7, "url": "https://example.com/a-150x150.jpg", "alt": "A", "caption": "", "sizeSlug": "thumbnail",
                 "href": NSNull(), "blockAttrs": NSNull(), "captionHTML": NSNull(), "extraClasses": ""],
                ["id": NSNull(), "url": "https://x.test/b.png", "alt": "", "caption": "B", "sizeSlug": "large"],
            ],
            "columns": 2, "cropped": false, "linkTo": "none",
        ]]
        let decoded = GalleryEdit(body: body)
        #expect(decoded?.images.map(\.url) == ["https://example.com/a-150x150.jpg", "https://x.test/b.png"])
        #expect(decoded?.images.first?.id == 7)
        #expect(decoded?.images.last?.id == nil)
        #expect(decoded?.images.last?.extraClasses == "")
        #expect(decoded?.cropped == false)
        #expect(decoded?.initialSizeSlug == "mixed")
    }

    @Test func galleryEditDecodesDefaultColumnsAsNil() {
        let body: [String: Any] = ["edit": [
            "images": [["id": 1, "url": "u", "sizeSlug": "large"]],
            "columns": NSNull(), "cropped": true, "linkTo": "none",
        ]]
        let decoded = GalleryEdit(body: body)
        #expect(decoded != nil)
        #expect(decoded?.columns == nil)
    }

    @Test func galleryPayloadKeepsDefaultColumnsWhenUntouched() throws {
        let existing = image(id: 1, url: "u")
        let payload = PostEditorView.galleryPayload(
            selections: [GallerySelection(existing: existing, media: try media(id: 1), id: 1)],
            columns: nil, cropped: true, linkTo: "none", sizeSlug: "large", editing: edit([existing]))
        #expect(payload["columns"] is NSNull)
    }

    @Test func galleryEditIsNilForAnInsertBody() {
        #expect(GalleryEdit(body: [String: Any]()) == nil)
    }

    @Test func customHTMLRequestReadsAnInsertBody() throws {
        let request = try #require(CustomHTMLRequest(body: [String: Any]()))
        #expect(request.html == nil)
        #expect(request.isEditing == false)
    }

    @Test func customHTMLRequestReadsAnEditBody() {
        #expect(CustomHTMLRequest(body: ["html": "<p>a</p>"])?.html == "<p>a</p>")
        #expect(CustomHTMLRequest(body: ["html": "<p>a</p>"])?.isEditing == true)
    }

    @Test func customHTMLRequestRejectsAMalformedBody() {
        #expect(CustomHTMLRequest(body: "x") == nil)
        #expect(CustomHTMLRequest(body: ["html": 3]) == nil)
    }

    @Test func customHTMLPartsSplitGutenbergsMarkedStyleAndScript() {
        let content = "<style data-wp-block-html=\"css\">\n.box { color: red; }\n</style>\n\n<script data-wp-block-html=\"js\">\ngo()\n</script>\n\n<div class=\"box\">Hi</div>"
        let parts = CustomHTMLParts(content: content)
        #expect(parts.html == "<div class=\"box\">Hi</div>")
        #expect(parts.css == ".box { color: red; }")
        #expect(parts.js == "go()")
        #expect(parts.content == content)
    }

    @Test func customHTMLPartsLeaveUnmarkedContentAsHTMLByteForByte() {
        let content = "\n<style>.a{}</style>\n<script>go()</script>\n<div>x</div>  "
        let parts = CustomHTMLParts(content: content)
        #expect(parts.html == content)
        #expect(parts.css.isEmpty && parts.js.isEmpty)
        #expect(parts.content == content)
    }

    @Test func customHTMLPartsLeaveACommentedOutMarkerAlone() {
        let content = "<!-- <script data-wp-block-html=\"js\">alert(1)</script> -->\n<div>x</div>"
        let parts = CustomHTMLParts(content: content)
        #expect(parts.js.isEmpty)
        #expect(parts.content == content)
    }

    @Test func customHTMLPartsOnlyReadMarkersWhereGutenbergWritesThem() {
        let content = "<div>x</div>\n<style data-wp-block-html=\"css\">.a{}</style>"
        #expect(CustomHTMLParts(content: content).html == content)
    }

    @Test func customHTMLPartsJoinInGutenbergsOrder() {
        let parts = CustomHTMLParts(html: "<p>a</p>", css: ".a{}", js: "go()")
        #expect(parts.content == "<style data-wp-block-html=\"css\">\n.a{}\n</style>\n\n<script data-wp-block-html=\"js\">\ngo()\n</script>\n\n<p>a</p>")
        #expect(CustomHTMLParts(html: "", css: ".a{}", js: "").content == "<style data-wp-block-html=\"css\">\n.a{}\n</style>")
    }

    @Test func customHTMLPartsReportWhetherTheyHoldCode() {
        #expect(CustomHTMLParts(content: "<p>a</p>").hasCode == false)
        #expect(CustomHTMLParts(html: "", css: "", js: "go()").hasCode)
        #expect(CustomHTMLParts(html: " ", css: "\n", js: "").isEmpty)
    }

    @Test func customHTMLScriptCarriesSpecialCharactersIntact() throws {
        let html = "<script>\"\\</script>😀\u{2028}"
        let script = try #require(EditorCoordinator.customHTMLScript(html: html, replace: true))
        #expect(script.hasPrefix("insertCustomHTML(") && script.hasSuffix(")"))
        let argument = String(script.dropFirst("insertCustomHTML(".count).dropLast())
        let json = try JSONDecoder().decode(String.self, from: Data(argument.utf8))
        let payload = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(payload["html"] as? String == html)
        #expect(payload["replace"] as? Bool == true)
    }

    @Test func galleryEditSharedSizeIsTheInitialSize() {
        let decoded = edit([image(id: 1, url: "a", sizeSlug: "medium"), image(id: 2, url: "b", sizeSlug: "medium")])
        #expect(decoded.initialSizeSlug == "medium")
    }

    @Test func galleryEditShowsKeepLinksForAttachmentGalleries() {
        #expect(edit([image(id: 1, url: "a", href: "https://example.com/att/")], linkTo: "attachment").showsKeepLinks)
        let media = edit([
            image(id: 1, url: "https://example.com/a.jpg", href: "https://example.com/a.jpg"),
            image(id: 2, url: "https://example.com/b.jpg", href: "https://example.com/b.jpg"),
        ], linkTo: "media")
        #expect(!media.showsKeepLinks)
    }

    @Test func galleryEditShowsKeepLinksForACustomLinkInAnUnlinkedGallery() {
        let mixed = edit([image(id: 1, url: "a", href: "https://example.com/wishlist"), image(id: 2, url: "b")], linkTo: "none")
        #expect(mixed.showsKeepLinks)
        #expect(!edit([image(id: 1, url: "a")], linkTo: "none").showsKeepLinks)
    }

    @Test func galleryPayloadKeepsUntouchedKeys() throws {
        let existing = image(id: 1, url: "https://example.com/p1-1024x683.jpg", href: "https://example.com/att/",
                             caption: "Hi", captionHTML: "<em>Hi</em>", blockAttrs: "{\"id\":1}", extraClasses: "image-plain")
        var withCarried = existing
        withCarried.extraAttrs = "{\"a\":[[\"target\",\"_blank\"]]}"
        let sel = GallerySelection(existing: withCarried, media: try media(id: 1), id: 1)
        let payload = PostEditorView.galleryPayload(
            selections: [sel], columns: 2, cropped: true, linkTo: "keep", sizeSlug: "large",
            editing: edit([withCarried], linkTo: "attachment"))
        let first = try #require(images(payload).first)
        #expect(first["extraAttrs"] as? String == "{\"a\":[[\"target\",\"_blank\"]]}")
        #expect(first["blockAttrs"] as? String == "{\"id\":1}")
        #expect(first["extraClasses"] as? String == "image-plain")
        #expect(first["captionHTML"] as? String == "<em>Hi</em>")
        #expect(payload["replace"] as? Bool == true)
    }

    @Test func galleryPayloadDropsCaptionHTMLWhenCaptionChanged() throws {
        let existing = image(id: 1, url: "u", caption: "Hi", captionHTML: "<em>Hi</em>")
        var sel = GallerySelection(existing: existing, media: try media(id: 1), id: 1)
        sel.caption = "Hello"
        let payload = PostEditorView.galleryPayload(
            selections: [sel], columns: 2, cropped: true, linkTo: "none", sizeSlug: "large", editing: edit([existing]))
        let first = try #require(images(payload).first)
        #expect(first["captionHTML"] == nil || first["captionHTML"] is NSNull)
        #expect(first["caption"] as? String == "Hello")
    }

    @Test func galleryPayloadMixedKeepsEachSize() throws {
        let small = image(id: 1, url: "https://example.com/p1-150x150.jpg", sizeSlug: "thumbnail")
        let new = try media(id: 2)
        let payload = PostEditorView.galleryPayload(
            selections: [
                GallerySelection(existing: small, media: try media(id: 1), id: 1),
                GallerySelection(media: new, alt: "", caption: ""),
            ],
            columns: 2, cropped: true, linkTo: "none", sizeSlug: "mixed", editing: edit([small]))
        let out = images(payload)
        #expect(out[0]["sizeSlug"] as? String == "thumbnail")
        #expect(out[0]["url"] as? String == "https://example.com/p1-150x150.jpg")
        #expect(out[1]["sizeSlug"] as? String == "large")
        #expect(out[1]["url"] as? String == new.sizedURL(for: "large"))
        #expect(payload["sizeSlug"] == nil)
    }

    @Test func galleryPayloadPickedSizeAppliesToEveryImage() throws {
        let small = image(id: 1, url: "https://example.com/p1-150x150.jpg", sizeSlug: "thumbnail")
        let payload = PostEditorView.galleryPayload(
            selections: [GallerySelection(existing: small, media: try media(id: 1), id: 1)],
            columns: 2, cropped: true, linkTo: "none", sizeSlug: "large", editing: edit([small]))
        let first = try #require(images(payload).first)
        #expect(first["sizeSlug"] as? String == "large")
        #expect(first["url"] as? String == "https://example.com/p1-1024x683.jpg")
    }

    @Test func galleryPayloadUnchangedSizeKeepsEachImagesOwnURL() throws {
        let edited = image(id: 1, url: "https://example.com/p1-e1790000000-1024x683.jpg")
        let new = try media(id: 2)
        let payload = PostEditorView.galleryPayload(
            selections: [
                GallerySelection(existing: edited, media: try media(id: 1), id: 1),
                GallerySelection(media: new, alt: "", caption: ""),
            ],
            columns: 2, cropped: true, linkTo: "none", sizeSlug: "large", editing: edit([edited]))
        let out = images(payload)
        #expect(out[0]["url"] as? String == "https://example.com/p1-e1790000000-1024x683.jpg")
        #expect(out[0]["sizeSlug"] as? String == "large")
        #expect(out[1]["url"] as? String == new.sizedURL(for: "large"))
    }

    @Test func galleryPayloadUnchangedSharedSizeGivesNewImagesThatSize() throws {
        let thumb = image(id: 1, url: "https://example.com/p1-150x150.jpg", sizeSlug: "thumbnail")
        let new = try media(id: 2)
        let payload = PostEditorView.galleryPayload(
            selections: [
                GallerySelection(existing: thumb, media: try media(id: 1), id: 1),
                GallerySelection(media: new, alt: "", caption: ""),
            ],
            columns: 2, cropped: true, linkTo: "none", sizeSlug: "thumbnail", editing: edit([thumb]))
        let out = images(payload)
        #expect(out[0]["url"] as? String == "https://example.com/p1-150x150.jpg")
        #expect(out[1]["sizeSlug"] as? String == "thumbnail")
        #expect(out[1]["url"] as? String == new.sizedURL(for: "thumbnail"))
    }

    @Test func galleryPayloadKeepLinksLinksNewImagesByGalleryLinkTo() throws {
        let existing = image(id: 1, url: "u", href: "https://example.com/att-1/")
        let new = try media(id: 2, link: "https://example.com/att-2/")
        let payload = PostEditorView.galleryPayload(
            selections: [
                GallerySelection(existing: existing, media: try media(id: 1), id: 1),
                GallerySelection(media: new, alt: "", caption: ""),
            ],
            columns: 2, cropped: true, linkTo: "keep", sizeSlug: "large", editing: edit([existing], linkTo: "attachment"))
        let out = images(payload)
        #expect(out[0]["href"] as? String == "https://example.com/att-1/")
        #expect(out[1]["href"] as? String == "https://example.com/att-2/")
        #expect(payload["keepLinks"] as? Bool == true)
        #expect(payload["linkTo"] as? String == "attachment")
        #expect(out[1]["blockAttrs"] as? String == "{\"id\":2,\"sizeSlug\":\"large\",\"linkDestination\":\"attachment\"}")
        #expect(out[0]["blockAttrs"] == nil)
    }

    @Test func galleryPayloadFullImageReplacesLinks() throws {
        let linked = image(id: 1, url: "u", href: "https://example.com/att-1/")
        let orphan = GalleryImage(
            id: nil, url: "https://x.test/h-300x200.png", fullUrl: "https://x.test/h.png", alt: "", caption: "",
            captionHTML: nil, sizeSlug: "medium", href: nil, blockAttrs: nil, extraClasses: "")
        let payload = PostEditorView.galleryPayload(
            selections: [
                GallerySelection(existing: linked, media: try media(id: 1), id: 1),
                GallerySelection(existing: orphan, media: nil, id: -1),
            ],
            columns: 2, cropped: true, linkTo: "media", sizeSlug: "large", editing: edit([linked, orphan], linkTo: "attachment"))
        let out = images(payload)
        #expect(out[0]["href"] as? String == "https://example.com/p1.jpg")
        #expect(out[1]["href"] as? String == "https://x.test/h.png")
        #expect(payload["keepLinks"] as? Bool == false)
    }

    @Test func galleryPayloadNoneUnlinksEveryImage() throws {
        let linked = image(id: 1, url: "u", href: "https://example.com/att-1/")
        let payload = PostEditorView.galleryPayload(
            selections: [GallerySelection(existing: linked, media: try media(id: 1), id: 1)],
            columns: 2, cropped: true, linkTo: "none", sizeSlug: "large", editing: edit([linked], linkTo: "attachment"))
        let first = try #require(images(payload).first)
        #expect(first["href"] is NSNull)
    }

    @Test func galleryPayloadImageWithoutMediaKeepsItsURL() throws {
        let orphan = image(id: nil, url: "https://x.test/hotlinked.png", sizeSlug: "medium")
        let payload = PostEditorView.galleryPayload(
            selections: [GallerySelection(existing: orphan, media: nil, id: -1)],
            columns: 2, cropped: true, linkTo: "none", sizeSlug: "large", editing: edit([orphan]))
        let first = try #require(images(payload).first)
        #expect(first["url"] as? String == "https://x.test/hotlinked.png")
        #expect(first["sizeSlug"] as? String == "medium")
        #expect(first["id"] == nil || first["id"] is NSNull)
    }

    @Test func galleryPayloadInsertKeepsTheInsertShape() throws {
        let new = try media(id: 2)
        let payload = PostEditorView.galleryPayload(
            selections: [GallerySelection(media: new, alt: "A", caption: "C")],
            columns: 3, cropped: false, linkTo: "media", sizeSlug: "thumbnail", editing: nil)
        let first = try #require(images(payload).first)
        #expect(Set(first.keys) == ["id", "url", "fullUrl", "alt", "caption"])
        #expect(first["url"] as? String == "https://example.com/p2-150x150.jpg")
        #expect(Set(payload.keys) == ["images", "columns", "cropped", "linkTo", "sizeSlug"])
    }

    @Test func galleryEditShowsKeepLinksForAFullImageGalleryWithOtherLinks() {
        let file = GalleryImage(
            id: 1, url: "https://example.com/a-1024x683.jpg", fullUrl: "https://example.com/a.jpg", alt: "", caption: "",
            captionHTML: nil, sizeSlug: "large", href: "https://example.com/a.jpg", blockAttrs: nil, extraClasses: "")
        #expect(!edit([file], linkTo: "media").showsKeepLinks)
        var custom = file
        custom.href = "https://example.com/about/"
        #expect(edit([file, custom], linkTo: "media").showsKeepLinks)
        var unlinked = file
        unlinked.href = nil
        #expect(edit([file, unlinked], linkTo: "media").showsKeepLinks)
    }

    @Test func galleryPayloadKeepLinksLinksNewImagesToTheFileInAFullImageGallery() throws {
        let existing = image(id: 1, url: "u", href: "https://example.com/about/")
        let new = try media(id: 2)
        let payload = PostEditorView.galleryPayload(
            selections: [
                GallerySelection(existing: existing, media: try media(id: 1), id: 1),
                GallerySelection(media: new, alt: "", caption: ""),
            ],
            columns: 2, cropped: true, linkTo: "keep", sizeSlug: "large", editing: edit([existing], linkTo: "media"))
        let out = images(payload)
        #expect(out[0]["href"] as? String == "https://example.com/about/")
        #expect(out[1]["href"] as? String == "https://example.com/p2.jpg")
        #expect(out[1]["blockAttrs"] == nil)
        #expect(payload["linkTo"] as? String == "media")
    }

    @Test func galleryPayloadKeepLinksLeavesNewImagesUnlinkedInAnUnlinkedGallery() throws {
        let existing = image(id: 1, url: "u", href: "https://example.com/wishlist")
        let payload = PostEditorView.galleryPayload(
            selections: [
                GallerySelection(existing: existing, media: try media(id: 1), id: 1),
                GallerySelection(media: try media(id: 2), alt: "", caption: ""),
            ],
            columns: 2, cropped: true, linkTo: "keep", sizeSlug: "large", editing: edit([existing], linkTo: "none"))
        let out = images(payload)
        #expect(out[0]["href"] as? String == "https://example.com/wishlist")
        #expect(out[1]["href"] is NSNull)
        #expect(payload["linkTo"] as? String == "none")
    }

    @Test func galleryPayloadFollowsTheSheetOrder() throws {
        let first = image(id: 1, url: "https://example.com/p1-1024x683.jpg")
        let second = image(id: 2, url: "https://example.com/p2-1024x683.jpg")
        let payload = PostEditorView.galleryPayload(
            selections: [
                GallerySelection(existing: second, media: try media(id: 2), id: 2),
                GallerySelection(existing: first, media: try media(id: 1), id: 1),
            ],
            columns: 2, cropped: true, linkTo: "none", sizeSlug: "mixed", editing: edit([first, second]))
        #expect(images(payload).compactMap { $0["id"] as? Int } == [2, 1])
        #expect(images(payload).compactMap { $0["url"] as? String } == [second.url, first.url])
    }
}
