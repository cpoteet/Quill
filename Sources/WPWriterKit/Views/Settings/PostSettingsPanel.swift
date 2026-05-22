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
        .background(Color.wpPanelBg)
    }

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
        }
    }

    private var publishDateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Publish Date")
            Toggle("Schedule", isOn: Binding(
                get: { settings.publishDate != nil },
                set: { settings.publishDate = $0 ? (settings.publishDate ?? Date().addingTimeInterval(3600)) : nil }
            ))
            .toggleStyle(.switch)
            if settings.publishDate != nil {
                DatePicker("", selection: Binding(
                    get: { settings.publishDate ?? Date() },
                    set: { settings.publishDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Categories")
            if categories.isEmpty {
                Text("No categories").font(.caption).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
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
                .frame(maxHeight: 210)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Tags")
            if tags.isEmpty {
                Text("No tags").font(.caption).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
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
                .frame(maxHeight: 160)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.0)
    }

    private var excerptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Excerpt")
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
