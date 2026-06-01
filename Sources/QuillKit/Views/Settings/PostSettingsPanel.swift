import SwiftUI

public struct PostSettings: Equatable {
    public var status: String = "draft"
    public var publishDate: Date? = nil
    public var categoryIDs: Set<Int> = []
    public var tagIDs: Set<Int> = []
    public var featuredMediaID: Int = 0
    public var excerpt: String = ""
    public var slug: String = ""
    public var commentStatus: String = "open"
    public var parentID: Int = 0
    public var newTagNames: [String] = []
    public var newCategoryNames: [String] = []

    public init() {}

    public mutating func setScheduled(_ enabled: Bool) {
        if enabled {
            if publishDate == nil { publishDate = Date().addingTimeInterval(3600) }
            status = "future"
        } else {
            publishDate = nil
            if status == "future" { status = "draft" }
        }
    }
}

public struct PostSettingsPanel: View {
    @Binding var settings: PostSettings
    let postType: String
    let categories: [WPCategory]
    let tags: [WPTag]
    let pages: [WPPost]

    @State private var categorySearch = ""
    @State private var tagSearch = ""

    public init(
        settings: Binding<PostSettings>,
        postType: String,
        categories: [WPCategory],
        tags: [WPTag],
        pages: [WPPost] = []
    ) {
        self._settings = settings
        self.postType = postType
        self.categories = categories
        self.tags = tags
        self.pages = pages
    }

    private var isPage: Bool { postType == "page" }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusSection
                publishDateSection
                if isPage { parentSection }
                if !isPage { categoriesSection }
                if !isPage { tagsSection }
                slugSection
                if !isPage { excerptSection }
                discussionSection
            }
            .padding(16)
        }
        .frame(width: 260)
        .background(Color.wpPanelBg)
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Status")
            Picker("Status", selection: $settings.status) {
                Text("Draft").tag("draft")
                Text("Published").tag("publish")
                Text("Scheduled").tag("future")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: settings.status) { _ in
                if settings.status == "future" {
                    if settings.publishDate == nil {
                        settings.publishDate = Date().addingTimeInterval(3600)
                    }
                } else {
                    settings.publishDate = nil
                }
            }
        }
    }

    // MARK: - Publish Date

    private var publishDateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Publish Date")
            Toggle(
                "Schedule",
                isOn: Binding(
                    get: { settings.publishDate != nil },
                    set: { settings.setScheduled($0) }
                )
            )
            .toggleStyle(.switch)
            if settings.publishDate != nil {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { settings.publishDate ?? Date() },
                        set: { settings.publishDate = $0 }
                    ), displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
            }
        }
    }

    // MARK: - Categories

    private var filteredCategories: [WPCategory] {
        let q = categorySearch.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var hasExactCategoryMatch: Bool {
        let q = categorySearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return categories.contains { $0.name.lowercased() == q }
            || settings.newCategoryNames.contains { $0.lowercased() == q }
    }

    private func addCategoryFromSearch() {
        let q = categorySearch.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if let match = categories.first(where: { $0.name.lowercased() == q.lowercased() }) {
            settings.categoryIDs.insert(match.id)
        } else if !settings.newCategoryNames.contains(where: { $0.lowercased() == q.lowercased() }) {
            settings.newCategoryNames.append(q)
        }
        categorySearch = ""
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Categories")
            VStack(spacing: 0) {
                searchBar(
                    placeholder: "Filter or add category…", text: $categorySearch, onSubmit: addCategoryFromSearch)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredCategories) { cat in
                            Toggle(
                                cat.name,
                                isOn: Binding(
                                    get: { settings.categoryIDs.contains(cat.id) },
                                    set: { on in
                                        if on {
                                            settings.categoryIDs.insert(cat.id)
                                        } else {
                                            settings.categoryIDs.remove(cat.id)
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                        }

                        ForEach(settings.newCategoryNames, id: \.self) { name in
                            newTaxonomyRow(name: name) {
                                settings.newCategoryNames.removeAll { $0 == name }
                            }
                        }

                        let trimmed = categorySearch.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && !hasExactCategoryMatch {
                            addNewRow(label: trimmed) { addCategoryFromSearch() }
                        }

                        if filteredCategories.isEmpty && settings.newCategoryNames.isEmpty
                            && categorySearch.trimmingCharacters(in: .whitespaces).isEmpty
                        {
                            emptyLabel("No categories")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 168)
                .scrollIndicators(.visible)
            }
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator, lineWidth: 1))
        }
    }

    // MARK: - Tags

    private var selectedTagNames: [String] {
        tags.filter { settings.tagIDs.contains($0.id) }.map { $0.name }
            + settings.newTagNames
    }

    private var filteredUnselectedTags: [WPTag] {
        let q = tagSearch.trimmingCharacters(in: .whitespaces)
        let unselected = tags.filter { !settings.tagIDs.contains($0.id) }
        guard !q.isEmpty else { return unselected }
        return unselected.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var hasExactTagMatch: Bool {
        let q = tagSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return tags.contains { $0.name.lowercased() == q }
            || settings.newTagNames.contains { $0.lowercased() == q }
    }

    private func addTagFromSearch() {
        let q = tagSearch.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if let match = tags.first(where: { $0.name.lowercased() == q.lowercased() }) {
            settings.tagIDs.insert(match.id)
        } else if !settings.newTagNames.contains(where: { $0.lowercased() == q.lowercased() }) {
            settings.newTagNames.append(q)
        }
        tagSearch = ""
    }

    private func removeTagName(_ name: String) {
        if let tag = tags.first(where: { $0.name == name }) {
            settings.tagIDs.remove(tag.id)
        } else {
            settings.newTagNames.removeAll { $0 == name }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Tags")
            VStack(spacing: 0) {
                if !selectedTagNames.isEmpty {
                    TagChipGrid(names: selectedTagNames, onRemove: removeTagName)
                        .padding(7)
                    Divider()
                }

                searchBar(placeholder: "Search or add tags…", text: $tagSearch, onSubmit: addTagFromSearch)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredUnselectedTags) { tag in
                            Button(tag.name) {
                                settings.tagIDs.insert(tag.id)
                                tagSearch = ""
                            }
                            .buttonStyle(TaxonomyRowStyle())
                        }

                        let trimmed = tagSearch.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && !hasExactTagMatch {
                            addNewRow(label: trimmed) { addTagFromSearch() }
                        }

                        if filteredUnselectedTags.isEmpty
                            && tagSearch.trimmingCharacters(in: .whitespaces).isEmpty
                            && tags.isEmpty
                        {
                            emptyLabel("No tags")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 156)
                .scrollIndicators(.visible)
            }
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator, lineWidth: 1))
        }
    }

    // MARK: - Parent Page

    private var parentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Parent Page")
            Picker("Parent", selection: $settings.parentID) {
                Text("None (top-level)").tag(0)
                ForEach(pages) { page in
                    Text(page.title.rendered).tag(page.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Slug

    private var slugSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Slug")
            TextField("", text: $settings.slug)
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(7)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator, lineWidth: 1))
        }
    }

    // MARK: - Excerpt

    private var excerptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Excerpt")
            TextEditor(text: $settings.excerpt)
                .scrollContentBackground(.hidden)
                .font(.callout)
                .frame(height: 56)
                .padding(7)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator, lineWidth: 1))
        }
    }

    // MARK: - Discussion

    private var discussionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Discussion")
            Toggle(
                "Allow comments",
                isOn: Binding(
                    get: { settings.commentStatus == "open" },
                    set: { settings.commentStatus = $0 ? "open" : "closed" }
                )
            )
            .toggleStyle(.switch)
        }
    }

    // MARK: - Shared subviews

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.0)
    }

    private func searchBar(placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private func newTaxonomyRow(name: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(Color.wpAmber)
                .font(.system(size: 13))
            Text(name)
                .font(.callout)
            Spacer()
            Text("new")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.wpAmber)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.wpAmber.opacity(0.12), in: Capsule())
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private func addNewRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Add \"\(label)\"", systemImage: "plus")
                .font(.callout)
                .foregroundStyle(Color.wpAmber)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }
}

// MARK: - Supporting views

private struct TagChipGrid: View {
    let names: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(names, id: \.self) { name in
                HStack(spacing: 3) {
                    Text(name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Button {
                        onRemove(name)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, in: proposal.replacingUnspecifiedDimensions().width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, in: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private struct LayoutResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
    }

    private func layout(subviews: Subviews, in maxWidth: CGFloat) -> LayoutResult {
        var result = LayoutResult()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            result.frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        result.size = CGSize(width: maxWidth, height: y + rowHeight)
        return result
    }
}

private struct TaxonomyRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : .clear)
            .contentShape(Rectangle())
    }
}
