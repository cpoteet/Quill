import QuillKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--check-fixtures"), i + 1 < args.count {
    FixtureCheck.run(directory: args[i + 1])
} else {
    QuillApp.main()
}
