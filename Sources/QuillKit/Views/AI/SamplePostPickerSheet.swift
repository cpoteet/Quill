import SwiftUI

/// Sheet that lets the user pick 2–5 WordPress posts as writing-style samples.
struct SamplePostPickerSheet: View {
    let posts: [WPPost]
    @Binding var selectedIDs: [Int]
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose Style Samples")
                    .font(.headline)
                Text("Select up to 5 posts that represent your writing style. Claude will match your voice generating and evaluating content.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            if posts.isEmpty {
                ContentUnavailableView("No Posts", systemImage: "doc.text",
                                       description: Text("Publish a post to use it as a writing sample."))
            } else {
                List(posts) { post in
                    postToggle(post)
                }
            }

            Divider()

            HStack(spacing: 12) {
                if selectedIDs.count >= 5 {
                    Text("Maximum 5 samples selected.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 440, height: 480)
    }

    private func postToggle(_ post: WPPost) -> some View {
        let isSelected = selectedIDs.contains(post.id)
        let atLimit = selectedIDs.count >= 5 && !isSelected
        return Toggle(
            post.title.rendered.isEmpty ? "Untitled" : post.title.decodedTitle,
            isOn: Binding(
                get: { isSelected },
                set: { on in
                    if on {
                        guard !atLimit else { return }
                        selectedIDs.append(post.id)
                    } else {
                        selectedIDs.removeAll { $0 == post.id }
                    }
                }
            )
        )
        .toggleStyle(.checkbox)
        .lineLimit(1)
        .disabled(atLimit)
    }
}
