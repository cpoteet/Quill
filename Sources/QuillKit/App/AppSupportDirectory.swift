import Foundation

/// Resolves (and creates) the `~/Library/Application Support/Quill` directory used for
/// credentials, AI settings, and the local SQLite database.
///
/// The directory is created with `0700` permissions so its contents are owner-only
/// regardless of per-file timing — closing the brief world-readable window that exists
/// between `Data.write(.atomic)` and the subsequent per-file `chmod 600`.
///
/// Tests set `override` to a temporary directory so they never touch the real user data.
enum AppSupportDirectory {
    /// When non-nil, all stores use this directory instead of the real Application Support
    /// path. Set by tests to isolate from (and avoid destroying) real user credentials.
    nonisolated(unsafe) static var override: URL?

    /// True when the process was launched by `swift test` or Xcode's test runner.
    /// Used by the safety guard in `directory()` to catch missing test isolation early.
    static var isRunningUnderTestRunner: Bool {
        // swift test wraps the binary in a .xctest bundle; the process name ends in
        // ".xctest". This covers both swift-testing and XCTest on all platforms.
        ProcessInfo.processInfo.processName.hasSuffix(".xctest")
    }

    /// Returns the Quill data directory, creating it if needed.
    static func directory() throws -> URL {
        if let override {
            try FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }

        // Safety guard: if we reach here while running under swift test, a test suite
        // is reading/writing the REAL user data directory without having set
        // AppSupportDirectory.override — this is a test-isolation bug.
        // Fix: set AppSupportDirectory.override to a temp dir in your suite's init().
        precondition(
            !isRunningUnderTestRunner,
            "AppSupportDirectory.directory() reached the real path during a test run. "
            + "Set AppSupportDirectory.override to a temp dir in your suite's init()."
        )
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Quill", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        // `attributes:` is only applied when the directory is first created; tighten any
        // pre-existing directory that may have been created with a looser umask.
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: dir.path
        )
        return dir
    }

    /// Convenience: the directory path joined with a file name.
    static func fileURL(_ name: String) throws -> URL {
        try directory().appendingPathComponent(name)
    }
}
