import Foundation

/// One passed schedule; a rescheduled post gets a new key, so an old confirmation never carries over.
public struct MissedKey: Hashable, Sendable {
    public let id: Int
    public let dateGmt: String
}

enum Masthead {
    static let scheduleWindow: TimeInterval = 14 * 86400
    static let missedGrace: TimeInterval = 5 * 60
    static let scheduledLimit = 3
    static let leadLimit = 3

    struct Lead: Equatable {
        let item: PostItem
        let section: SidebarSection
        let edited: Date
        let meta: String
    }

    struct ScheduledRow: Equatable {
        let post: WPPost
        let date: Date
        let missed: Bool
    }

    // MARK: - Continue writing

    static func leads(for section: SidebarSection, posts: [WPPost], pages: [WPPost], localDrafts: [LocalDraft],
                      stashes: [StashTime], userID: Int?, now: Date, locale: Locale = .autoupdatingCurrent) -> [Lead] {
        let stashed = Dictionary(stashes.map { ($0.postID, $0.savedAt) }, uniquingKeysWith: max)
        let remote: [WPPost]
        let local: [LocalDraft]
        switch section {
        case .posts:
            remote = posts.filter { stashed[$0.id] != nil || isOwnDraft($0, userID: userID) }
                + pages.filter { stashed[$0.id] != nil }
            local = localDrafts
        case .pages:
            remote = pages.filter { stashed[$0.id] != nil || isOwnDraft($0, userID: userID) }
            local = []
        case .localDrafts:
            remote = []
            local = localDrafts
        case .media:
            return []
        }

        let remoteLeads = remote.compactMap { post -> (Lead, Int64)? in
            let modified = PostSettings.parseWPDate(post.modifiedGmt)
            let stash = stashed[post.id]
            guard let edited = [modified, stash].compactMap({ $0 }).max() else { return nil }
            let meta = stash != nil
                ? "\(PostListRow.statusLabel(post.status)) · unsaved changes on this Mac"
                : "Draft · edited \(editedPhrase(edited, now: now, locale: locale))"
            let home: SidebarSection = post.type == "page" ? .pages : .posts
            return (Lead(item: .remote(post), section: home, edited: edited, meta: meta), Int64(post.id))
        }
        let localLeads = local.map { draft -> (Lead, Int64) in
            let kind = draft.type == "page" ? "Page" : "Post"
            let meta = "\(kind) draft · on this Mac · edited \(editedPhrase(draft.updatedAt, now: now, locale: locale))"
            return (Lead(item: .local(draft), section: .localDrafts, edited: draft.updatedAt, meta: meta), draft.id)
        }

        let newestFirst = (remoteLeads + localLeads).sorted { a, b in
            if a.0.edited != b.0.edited { return a.0.edited > b.0.edited }
            if a.0.item.isRemote != b.0.item.isRemote { return a.0.item.isRemote }
            return a.1 < b.1
        }
        return newestFirst.prefix(leadLimit).map(\.0)
    }

    private static func isOwnDraft(_ post: WPPost, userID: Int?) -> Bool {
        post.status == "draft" && (userID == nil || post.author == userID)
    }

    static func editedPhrase(_ date: Date, now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        let date = min(date, now)
        guard now.timeIntervalSince(date) < 7 * 86400 else {
            return date.formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated))
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    // MARK: - Recently edited

    static func recentlyEdited(for section: SidebarSection, posts: [WPPost], pages: [WPPost], userID: Int?,
                               now: Date, locale: Locale = .autoupdatingCurrent) -> [Lead] {
        let list: [WPPost]
        let home: SidebarSection
        switch section {
        case .posts: (list, home) = (posts, .posts)
        case .pages: (list, home) = (pages, .pages)
        case .localDrafts, .media: return []
        }
        let edits = list.compactMap { post -> (post: WPPost, edited: Date)? in
            guard post.status != "future", userID == nil || post.author == userID,
                  let edited = PostSettings.parseWPDate(post.modifiedGmt) else { return nil }
            return (post, edited)
        }
        let newestFirst = edits.sorted { a, b in
            a.edited != b.edited ? a.edited > b.edited : a.post.id < b.post.id
        }
        return newestFirst.prefix(leadLimit).map { post, edited in
            let meta = "\(PostListRow.statusLabel(post.status)) · edited \(editedPhrase(edited, now: now, locale: locale))"
            return Lead(item: .remote(post), section: home, edited: edited, meta: meta)
        }
    }

    // MARK: - Scheduled

    static func scheduled(for section: SidebarSection, posts: [WPPost], pages: [WPPost],
                          confirmedMissed: Set<MissedKey>, now: Date) -> [ScheduledRow] {
        let list: [WPPost]
        switch section {
        case .posts: list = posts
        case .pages: list = pages
        case .localDrafts, .media: return []
        }
        let rows = list.compactMap { post -> ScheduledRow? in
            guard post.status == "future", let date = PostSettings.parseWPDate(post.dateGmt) else { return nil }
            if date < now - missedGrace {
                guard confirmedMissed.contains(MissedKey(id: post.id, dateGmt: post.dateGmt)) else { return nil }
                return ScheduledRow(post: post, date: date, missed: true)
            }
            guard date <= now + scheduleWindow else { return nil }
            return ScheduledRow(post: post, date: date, missed: false)
        }
        let sorted = rows.sorted { a, b in
            a.missed != b.missed ? a.missed : a.date < b.date
        }
        return Array(sorted.prefix(scheduledLimit))
    }

    static func missedCandidates(posts: [WPPost], now: Date) -> [MissedKey] {
        posts.compactMap { post in
            guard post.status == "future", let date = PostSettings.parseWPDate(post.dateGmt),
                  date < now - missedGrace else { return nil }
            return MissedKey(id: post.id, dateGmt: post.dateGmt)
        }
    }

    static func scheduleDate(_ date: Date, locale: Locale = .autoupdatingCurrent,
                             timeZone: TimeZone = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone)
            .weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    // MARK: - Copy

    static func emptyLine(for section: SidebarSection, sectionIsEmpty: Bool) -> String {
        let noun = section == .pages ? "page" : section == .localDrafts ? "draft" : "post"
        return sectionIsEmpty ? "No \(noun)s yet" : "Select a \(noun) to edit"
    }

    static func spokenLabel(_ heading: String, title: String, detail: String) -> String {
        [heading, title, detail.replacingOccurrences(of: " · ", with: ", ")].joined(separator: ", ")
    }

    static func displayName(siteName: String?, siteURL: URL) -> String {
        if let siteName, !siteName.isEmpty { return siteName }
        return siteURL.host() ?? siteURL.absoluteString
    }
}
