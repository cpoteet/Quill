import SwiftUI

/// Sheet that lets the user pick 2–5 WordPress posts as writing-style samples.
struct SamplePostPickerSheet: View {
    let posts: [WPPost]
    @Binding var selectedIDs: [Int]
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Choose Style Samples")
                    .font(.headline)
                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.wpAmber)
            }
            .padding()

            Divider()

            Text("Select up to 5 posts that represent your writing style. Claude will match your voice generating and evaluating content.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if posts.isEmpty {
                Spacer()
                Text("No posts available.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(posts) { post in
                            let isSelected = selectedIDs.contains(post.id)
                            let atLimit = selectedIDs.count >= 5 && !isSelected
                            Button {
                                if isSelected {
                                    selectedIDs.removeAll { $0 == post.id }
                                } else if !atLimit {
                                    selectedIDs.append(post.id)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.wpAmber : .secondary)
                                    Text(post.title.rendered.isEmpty ? "Untitled" : post.title.rendered)
                                        .foregroundStyle(atLimit && !isSelected ? .secondary : .primary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(atLimit)
                            Divider().padding(.leading)
                        }
                    }
                }
            }

            if selectedIDs.count >= 5 {
                Text("Maximum 5 samples selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 440, height: 480)
    }
}
