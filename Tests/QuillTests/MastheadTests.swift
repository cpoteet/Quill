import Foundation
import Testing
@testable import QuillKit

private let now = PostSettings.parseWPDate("2026-10-31T12:00:00")!
private let gb = Locale(identifier: "en_GB")

private func gmt(_ offset: TimeInterval) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: now.addingTimeInterval(offset))
}

private func post(_ id: Int, status: String = "draft", type: String = "post", title: String = "Post",
                  modified: TimeInterval = -3600, scheduled: TimeInterval? = nil, author: Int? = 1) throws -> WPPost {
    let authorField = author.map { #""author":\#($0),"# } ?? ""
    let dateGmt = scheduled.map(gmt) ?? gmt(modified)
    let json = """
    {"id":\(id),"type":"\(type)","title":{"rendered":"\(title)"},"status":"\(status)",
     "date":"\(dateGmt)","date_gmt":"\(dateGmt)","modified":"\(gmt(modified))","modified_gmt":"\(gmt(modified))",
     \(authorField)"slug":"s","link":"l"}
    """
    return try JSONDecoder().decode(WPPost.self, from: Data(json.utf8))
}

private func draft(_ id: Int64, type: String = "post", title: String = "Local", updated: TimeInterval) -> LocalDraft {
    LocalDraft(id: id, title: title, content: "", excerpt: "", type: type, footnotes: "",
               createdAt: now, updatedAt: now.addingTimeInterval(updated))
}

private func leads(_ section: SidebarSection, posts: [WPPost] = [], pages: [WPPost] = [],
                   drafts: [LocalDraft] = [], stashes: [StashTime] = [], userID: Int? = nil) -> [Masthead.Lead] {
    Masthead.leads(for: section, posts: posts, pages: pages, localDrafts: drafts, stashes: stashes,
                   userID: userID, now: now, locale: gb)
}

private func lead(_ section: SidebarSection, posts: [WPPost] = [], pages: [WPPost] = [],
                  drafts: [LocalDraft] = [], stashes: [StashTime] = [], userID: Int? = nil) -> Masthead.Lead? {
    leads(section, posts: posts, pages: pages, drafts: drafts, stashes: stashes, userID: userID).first
}

@Suite struct MastheadLeadTests {
    @Test func postsLeadPrefersANewerLocalDraft() throws {
        let result = lead(.posts, posts: [try post(1, modified: -7200)], drafts: [draft(5, updated: -60)])
        #expect(result?.item == .local(draft(5, updated: -60)))
        #expect(result?.section == .localDrafts)
    }

    @Test func postsLeadPrefersANewerWordPressDraft() throws {
        let remote = try post(1, modified: -60)
        let result = lead(.posts, posts: [remote], drafts: [draft(5, updated: -7200)])
        #expect(result?.item == .remote(remote))
        #expect(result?.section == .posts)
        #expect(result?.meta == "Draft · edited 1 minute ago")
    }

    @Test func aStashedPublishedPostLeadsWithItsMetaLine() throws {
        let published = try post(2, status: "publish", modified: -86400 * 30)
        let result = lead(.posts, posts: [try post(1, modified: -7200), published],
                          stashes: [StashTime(postID: 2, savedAt: now.addingTimeInterval(-60))])
        #expect(result?.item == .remote(published))
        #expect(result?.meta == "Published · unsaved changes on this Mac")
        #expect(result?.edited == now.addingTimeInterval(-60))
    }

    @Test func aStashedPageLeadsThePostsPageAndLivesInPages() throws {
        let page = try post(3, status: "publish", type: "page", modified: -86400)
        let result = lead(.posts, pages: [page], stashes: [StashTime(postID: 3, savedAt: now.addingTimeInterval(-60))])
        #expect(result?.item == .remote(page))
        #expect(result?.section == .pages)
    }

    @Test func pageDraftsWithoutAStashStayOffThePostsPage() throws {
        #expect(lead(.posts, pages: [try post(3, type: "page")]) == nil)
    }

    @Test func aStashForAPostNoLongerListedIsIgnored() throws {
        let result = lead(.posts, posts: [try post(1, modified: -7200)],
                          stashes: [StashTime(postID: 99, savedAt: now)])
        #expect(result?.item.id == "remote-1")
    }

    @Test func anotherAuthorsDraftIsSkippedOnceTheUserIsKnown() throws {
        let mine = try post(1, modified: -7200, author: 1)
        let theirs = try post(2, modified: -60, author: 2)
        #expect(lead(.posts, posts: [mine, theirs], userID: 1)?.item == .remote(mine))
    }

    @Test func anotherAuthorsDraftCountsBeforeTheUserIsKnown() throws {
        let mine = try post(1, modified: -7200, author: 1)
        let theirs = try post(2, modified: -60, author: 2)
        #expect(lead(.posts, posts: [mine, theirs], userID: nil)?.item == .remote(theirs))
    }

    @Test func pendingPostsNeverLead() throws {
        #expect(lead(.posts, posts: [try post(1, status: "pending", modified: -60)]) == nil)
    }

    @Test func pagesLeadIgnoresLocalDraftsAndPosts() throws {
        let page = try post(3, type: "page", modified: -7200)
        let result = lead(.pages, posts: [try post(1, modified: -60)], pages: [page],
                          drafts: [draft(5, type: "page", updated: -60)])
        #expect(result?.item == .remote(page))
        #expect(result?.section == .pages)
    }

    @Test func draftsLeadIgnoresRemotePosts() throws {
        let local = draft(5, updated: -7200)
        let result = lead(.localDrafts, posts: [try post(1, modified: -60)], drafts: [local],
                          stashes: [StashTime(postID: 1, savedAt: now)])
        #expect(result?.item == .local(local))
    }

    @Test func theNewestThreeLeadInOrder() throws {
        let posts = [try post(1, modified: -400), try post(2, modified: -100), try post(3, modified: -300)]
        let drafts = [draft(7, updated: -200), draft(8, updated: -500)]
        #expect(leads(.posts, posts: posts, drafts: drafts).map(\.item.id) == ["remote-2", "local-7", "remote-3"])
    }

    @Test func fewerCandidatesGiveFewerRows() throws {
        #expect(leads(.posts, posts: [try post(1)], drafts: [draft(7, updated: -60)]).count == 2)
        #expect(leads(.posts).isEmpty)
    }

    @Test func mediaHasNoLead() {
        #expect(lead(.media, drafts: [draft(5, updated: -60)]) == nil)
    }

    @Test func untitledLocalDraftShowsUntitled() {
        #expect(lead(.localDrafts, drafts: [draft(5, title: "", updated: -60)])?.item.title == "Untitled")
    }

    @Test func tiesResolveRemoteFirstThenLowerID() throws {
        let remoteHigh = try post(9, modified: -60)
        let remoteLow = try post(4, modified: -60)
        let local = draft(1, updated: -60)
        #expect(lead(.posts, posts: [remoteHigh, remoteLow], drafts: [local])?.item == .remote(remoteLow))
    }

    @Test func localDraftMetaNamesItsType() {
        #expect(lead(.localDrafts, drafts: [draft(5, type: "page", updated: -86400)])?.meta
                == "Page draft · on this Mac · edited yesterday")
        #expect(lead(.localDrafts, drafts: [draft(5, updated: -86400)])?.meta
                == "Post draft · on this Mac · edited yesterday")
    }

    @Test func aClockAheadOfTheDeviceReadsAsNow() {
        #expect(Masthead.editedPhrase(now.addingTimeInterval(3600), now: now, locale: gb)
                == Masthead.editedPhrase(now, now: now, locale: gb))
    }

    @Test func aDraftWithoutAModifiedTimeLeadsOnlyThroughItsStash() throws {
        let json = #"{"id":1,"type":"post","title":{"rendered":"T"},"status":"draft","date":"d","modified":"m","slug":"s","link":"l","author":1}"#
        let undated = try JSONDecoder().decode(WPPost.self, from: Data(json.utf8))
        #expect(undated.modifiedGmt == "")
        #expect(lead(.posts, posts: [undated]) == nil)
        let stash = StashTime(postID: 1, savedAt: now.addingTimeInterval(-60))
        #expect(lead(.posts, posts: [undated], stashes: [stash])?.edited == stash.savedAt)
    }

    @Test func editedPhraseIsRelativeForAWeekThenADate() {
        #expect(Masthead.editedPhrase(now.addingTimeInterval(-7200), now: now, locale: gb) == "2 hours ago")
        #expect(Masthead.editedPhrase(now.addingTimeInterval(-86400), now: now, locale: gb) == "yesterday")
        #expect(Masthead.editedPhrase(now.addingTimeInterval(-86400 * 8), now: now, locale: gb) == "23 Oct")
    }
}

@Suite struct MastheadRecentlyEditedTests {
    private func recent(_ section: SidebarSection, posts: [WPPost] = [], pages: [WPPost] = [],
                        userID: Int? = nil) -> [Masthead.Lead] {
        Masthead.recentlyEdited(for: section, posts: posts, pages: pages, userID: userID, now: now, locale: gb)
    }

    @Test func listsAnyStatusNewestEditFirst() throws {
        let old = try post(1, status: "publish", modified: -86400 * 3)
        let newer = try post(2, status: "private", modified: -7200)
        let result = recent(.posts, posts: [old, newer])
        #expect(result.map(\.item) == [.remote(newer), .remote(old)])
        #expect(result.first?.meta == "Private · edited 2 hours ago")
        #expect(result.first?.section == .posts)
    }

    @Test func capsAtThree() throws {
        let posts = try (1...5).map { try post($0, status: "publish", modified: TimeInterval(-60 * $0)) }
        #expect(recent(.posts, posts: posts).map(\.item) == posts.prefix(3).map { .remote($0) })
    }

    @Test func leavesOutScheduledPosts() throws {
        #expect(recent(.posts, posts: [try post(1, status: "future", scheduled: 86400)]).isEmpty)
    }

    @Test func leavesOutAnotherAuthorsPostOnceTheUserIsKnown() throws {
        let theirs = try post(1, status: "publish", author: 2)
        #expect(recent(.posts, posts: [theirs]).count == 1)
        #expect(recent(.posts, posts: [theirs], userID: 1).isEmpty)
    }

    @Test func staysInsideItsOwnSection() throws {
        let page = try post(3, status: "publish", type: "page")
        let article = try post(1, status: "publish")
        #expect(recent(.posts, posts: [article], pages: [page]).map(\.item) == [.remote(article)])
        #expect(recent(.pages, posts: [article], pages: [page]).map(\.item) == [.remote(page)])
        #expect(recent(.pages, pages: [page]).first?.section == .pages)
        #expect(recent(.localDrafts, posts: [article], pages: [page]).isEmpty)
    }
}

@Suite struct MastheadScheduledTests {
    private func scheduled(_ section: SidebarSection, posts: [WPPost] = [], pages: [WPPost] = [],
                           missed: Set<MissedKey> = []) -> [Masthead.ScheduledRow] {
        Masthead.scheduled(for: section, posts: posts, pages: pages, confirmedMissed: missed, now: now)
    }

    @Test func scheduledKeepsTheNextTwoWeeksCappedAtThree() throws {
        let posts = [
            try post(1, status: "future", scheduled: 86400 * 3),
            try post(2, status: "future", scheduled: 86400 * 15),
            try post(3, status: "future", scheduled: 86400),
            try post(4, status: "future", scheduled: 86400 * 2),
            try post(5, status: "future", scheduled: 86400 * 4),
            try post(6, status: "draft", scheduled: 86400),
        ]
        let rows = scheduled(.posts, posts: posts)
        #expect(rows.map(\.post.id) == [3, 4, 1])
        #expect(rows.allSatisfy { !$0.missed })
    }

    @Test func missedComeFirstOnlyWhenConfirmed() throws {
        let upcoming = try post(1, status: "future", scheduled: 3600)
        let confirmed = try post(2, status: "future", scheduled: -3600)
        let unconfirmed = try post(3, status: "future", scheduled: -7200)
        let rows = scheduled(.posts, posts: [upcoming, confirmed, unconfirmed],
                             missed: [MissedKey(id: 2, dateGmt: confirmed.dateGmt)])
        #expect(rows.map(\.post.id) == [2, 1])
        #expect(rows.map(\.missed) == [true, false])
    }

    @Test func aConfirmationForAnEarlierScheduleDoesNotCarryOver() throws {
        let rescheduled = try post(2, status: "future", scheduled: -3600)
        let rows = scheduled(.posts, posts: [rescheduled], missed: [MissedKey(id: 2, dateGmt: gmt(-86400))])
        #expect(rows.isEmpty)
    }

    @Test func missedCountsTowardTheCapOfThree() throws {
        let posts = try (1...3).map { try post($0, status: "future", scheduled: 3600 * Double($0)) }
        let missed = try post(9, status: "future", scheduled: -3600)
        let rows = scheduled(.posts, posts: posts + [missed], missed: [MissedKey(id: 9, dateGmt: missed.dateGmt)])
        #expect(rows.map(\.post.id) == [9, 1, 2])
    }

    @Test func missedWaitsOutTheFiveMinuteGrace() throws {
        let late = try post(1, status: "future", scheduled: -240)
        #expect(Masthead.missedCandidates(posts: [late], now: now).isEmpty)
        let rows = scheduled(.posts, posts: [late], missed: [MissedKey(id: 1, dateGmt: late.dateGmt)])
        #expect(rows.map(\.missed) == [false])
        let overdue = try post(2, status: "future", scheduled: -360)
        #expect(Masthead.missedCandidates(posts: [late, overdue], now: now) == [MissedKey(id: 2, dateGmt: overdue.dateGmt)])
    }

    @Test func onlyScheduledPostsCanBeMissed() throws {
        let published = try post(1, status: "publish", scheduled: -86400)
        let draft = try post(2, status: "draft", scheduled: -86400)
        let missed = try post(3, status: "future", scheduled: -86400)
        #expect(Masthead.missedCandidates(posts: [published, draft, missed], now: now)
                == [MissedKey(id: 3, dateGmt: missed.dateGmt)])
    }

    @Test func pagesShowScheduledPages() throws {
        let page = try post(3, status: "future", type: "page", scheduled: 3600)
        let rows = scheduled(.pages, posts: [try post(1, status: "future", scheduled: 3600)], pages: [page])
        #expect(rows.map(\.post.id) == [3])
    }

    @Test func draftsSectionHasNoScheduled() throws {
        #expect(scheduled(.localDrafts, posts: [try post(1, status: "future", scheduled: 3600)]).isEmpty)
    }

    @Test func scheduleDateNamesTheWeekdayAndTime() {
        let tuesday = PostSettings.parseWPDate("2026-11-03T09:00:00")!
        let utc = TimeZone(identifier: "UTC")!
        #expect(Masthead.scheduleDate(tuesday, locale: Locale(identifier: "en_US"), timeZone: utc) == "Tue, Nov 3 at 9:00\u{202F}AM")
        #expect(Masthead.scheduleDate(tuesday, locale: gb, timeZone: utc) == "Tue 3 Nov at 09:00")
    }
}

@Suite struct MastheadCopyTests {
    @Test func displayNameFallsBackToHost() {
        let url = URL(string: "https://siolon.com/blog")!
        #expect(Masthead.displayName(siteName: nil, siteURL: url) == "siolon.com")
        #expect(Masthead.displayName(siteName: "", siteURL: url) == "siolon.com")
        #expect(Masthead.displayName(siteName: "Siolon", siteURL: url) == "Siolon")
    }

    @Test func spokenLabelReadsAsOnePhrase() {
        #expect(Masthead.spokenLabel("Continue writing", title: "Packing for the coast", detail: "Draft · edited 2 hours ago")
                == "Continue writing, Packing for the coast, Draft, edited 2 hours ago")
    }

    @Test func emptyLineAsksForASelectionWhenTheSectionHasItems() {
        #expect(Masthead.emptyLine(for: .posts, sectionIsEmpty: false) == "Select a post to edit")
        #expect(Masthead.emptyLine(for: .pages, sectionIsEmpty: false) == "Select a page to edit")
        #expect(Masthead.emptyLine(for: .localDrafts, sectionIsEmpty: false) == "Select a draft to edit")
    }

    @Test func emptyLineSaysTheSectionIsEmpty() {
        #expect(Masthead.emptyLine(for: .posts, sectionIsEmpty: true) == "No posts yet")
        #expect(Masthead.emptyLine(for: .pages, sectionIsEmpty: true) == "No pages yet")
        #expect(Masthead.emptyLine(for: .localDrafts, sectionIsEmpty: true) == "No drafts yet")
    }
}
