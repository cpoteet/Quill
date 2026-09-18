import Foundation
import QuillKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--check-fixtures") {
    guard i + 1 < args.count else {
        FileHandle.standardError.write(Data("usage: Quill --check-fixtures <fixtures directory>\n".utf8))
        exit(2)
    }
    FixtureCheck.run(directory: args[i + 1])
} else {
    QuillApp.main()
}
