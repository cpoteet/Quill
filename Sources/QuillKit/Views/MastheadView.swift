import SwiftUI

struct MastheadView: View {
    let section: SidebarSection
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var services: AppServices
    @State private var stashes: [StashTime] = []
    @State private var stashRevision = 0

    private struct StashReload: Hashable {
        let site: String?
        let posts: [WPPost]
        let pages: [WPPost]
        let revision: Int
    }

    var body: some View {
        if let credentials = appState.credentials {
            TimelineView(.everyMinute) { context in
                page(credentials: credentials, now: context.date)
                    .task(id: Masthead.missedCandidates(posts: appState.posts + appState.pages, now: context.date)) {
                        await appState.confirmMissedSchedules(now: context.date)
                    }
            }
            .task(id: credentials) { await appState.loadUnfilteredHTMLCapability() }
            .task(id: StashReload(site: credentials.siteKey, posts: appState.posts, pages: appState.pages,
                                  revision: stashRevision)) {
                stashes = (try? services.autosaveStore.stashTimes(site: credentials.siteKey)) ?? []
            }
            .onReceive(NotificationCenter.default.publisher(for: .autosavesDidChange, object: services.autosaveStore)
                .receive(on: RunLoop.main)) { _ in
                stashRevision += 1
            }
        }
    }

    @ViewBuilder
    private func page(credentials: Credentials, now: Date) -> some View {
        let name = Masthead.displayName(siteName: appState.siteName, siteURL: credentials.siteURL)
        let leads = Masthead.leads(for: section, posts: appState.posts, pages: appState.pages,
                                   localDrafts: appState.localDrafts, stashes: stashes,
                                   userID: appState.currentUserID, now: now)
        let scheduled = Masthead.scheduled(for: section, posts: appState.posts, pages: appState.pages,
                                           confirmedMissed: appState.confirmedMissed, now: now)
        if leads.isEmpty && scheduled.isEmpty {
            ContentUnavailableView {
                Label {
                    Text(name)
                } icon: {
                    QuillMark.emptyStateIcon
                }
            } description: {
                Text(Masthead.emptyLine(for: section, sectionIsEmpty: appState.sectionIsEmpty))
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(name: name, host: credentials.siteURL.host() ?? "")

                    if !leads.isEmpty {
                        group("Continue Writing") {
                            ForEach(Array(leads.enumerated()), id: \.element.item.id) { index, lead in
                                if index > 0 { Divider().padding(.leading, 40) }
                                MastheadRow(badge: lead.item.statusBadge, title: lead.item.title, detail: lead.meta,
                                            heading: "Continue writing") {
                                    appState.openFromMasthead(lead.item, in: lead.section)
                                }
                            }
                        }
                    }

                    if !scheduled.isEmpty {
                        group("Scheduled") {
                            ForEach(Array(scheduled.enumerated()), id: \.element.post.id) { index, row in
                                if index > 0 { Divider().padding(.leading, 40) }
                                scheduledRow(row)
                            }
                        }
                    }
                }
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 72)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func header(name: String, host: String) -> some View {
        HStack(spacing: 12) {
            if let icon = appState.siteIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator, lineWidth: 0.5))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.title.bold())
                    .lineLimit(1)
                Text(host)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func group<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0, content: rows)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func scheduledRow(_ row: Masthead.ScheduledRow) -> some View {
        let item = PostItem.remote(row.post)
        return MastheadRow(badge: row.missed ? "pending" : "future",
                           symbol: row.missed ? "exclamationmark.circle.fill" : nil,
                           title: item.title,
                           detail: row.missed ? "Missed schedule" : Masthead.scheduleDate(row.date),
                           heading: "Scheduled") {
            appState.openFromMasthead(item, in: row.post.type == "page" ? .pages : .posts)
        }
    }
}

private struct MastheadRow: View {
    let badge: String
    var symbol: String?
    let title: String
    let detail: String
    let heading: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol ?? statusSymbol(badge))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.statusColor(badge))
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Masthead.spokenLabel(heading, title: title, detail: detail))
    }
}
