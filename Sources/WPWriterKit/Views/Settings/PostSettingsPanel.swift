import SwiftUI

public struct PostSettings: Equatable {
    public var status: String = "draft"
    public var publishDate: Date? = nil
    public var categoryIDs: Set<Int> = []
    public var tagIDs: Set<Int> = []
    public var featuredMediaID: Int = 0
    public var excerpt: String = ""

    public init() {}
}

public struct PostSettingsPanel: View {
    @Binding var settings: PostSettings
    let categories: [WPCategory]
    let tags: [WPTag]

    public init(settings: Binding<PostSettings>, categories: [WPCategory], tags: [WPTag]) {
        self._settings = settings
        self.categories = categories
        self.tags = tags
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusSection
                publishDateSection
                categoriesSection
                tagsSection
                excerptSection
            }
            .padding(16)
        }
        .frame(width: 260)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Status", systemImage: "circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Picker("Status", selection: $settings.status) {
                Text("Draft").tag("draft")
                Text("Published").tag("publish")
                Text("Scheduled").tag("future")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var publishDateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Publish Date", systemImage: "calendar")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Toggle("Schedule", isOn: Binding(
                get: { settings.publishDate != nil },
                set: { settings.publishDate = $0 ? Date().addingTimeInterval(3600) : nil }
            ))
            .toggleStyle(.switch)
            if let date = Binding($settings.publishDate) {
                DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Categories", systemImage: "folder")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            if categories.isEmpty {
                Text("No categories").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(categories) { cat in
                    Toggle(cat.name, isOn: Binding(
                        get: { settings.categoryIDs.contains(cat.id) },
                        set: { checked in
                            if checked { settings.categoryIDs.insert(cat.id) }
                            else { settings.categoryIDs.remove(cat.id) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tags", systemImage: "tag")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            if tags.isEmpty {
                Text("No tags").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(tags) { tag in
                    Toggle(tag.name, isOn: Binding(
                        get: { settings.tagIDs.contains(tag.id) },
                        set: { checked in
                            if checked { settings.tagIDs.insert(tag.id) }
                            else { settings.tagIDs.remove(tag.id) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var excerptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Excerpt", systemImage: "text.alignleft")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            TextEditor(text: $settings.excerpt)
                .frame(height: 70)
                .font(.body)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.separator, lineWidth: 1)
                )
        }
    }
}
