import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {

            // MARK: Header
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .padding(.bottom, 4)

                Text("Quill")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))

                Text("Version 1.8.0")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("© 2026 Chris Poteet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Link("End User Licensing Agreement", destination: URL(string: "https://cpoteet.github.io/Quill-Releases/license.html")!)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)

            Divider()

            // MARK: Third-Party Notices
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Third-Party Notices")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .padding(.bottom, 2)

                    NoticeEntry(
                        name: "Tiptap",
                        url: "https://tiptap.dev",
                        copyright: "Copyright © 2025, Tiptap GmbH",
                        license: "MIT License"
                    )

                    NoticeEntry(
                        name: "ProseMirror",
                        url: "https://prosemirror.net",
                        copyright: "Copyright © 2015–2017 Marijn Haverbeke and others",
                        license: "MIT License"
                    )

                    NoticeEntry(
                        name: "SQLite.swift",
                        url: "https://github.com/stephencelis/SQLite.swift",
                        copyright: "Copyright © 2014–2015 Stephen Celis",
                        license: "MIT License"
                    )

                    NoticeEntry(
                        name: "Quill Icon",
                        url: "https://www.vecteezy.com/free-vector/quill",
                        copyright: "Quill Vectors by Vecteezy",
                        license: "Vecteezy Free License"
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 400, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - NoticeEntry

private struct NoticeEntry: View {
    let name: String
    let url: String
    let copyright: String
    let license: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 12, weight: .medium))

            if let dest = URL(string: url) {
                Link(url, destination: dest)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(copyright)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(license)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}
