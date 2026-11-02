import Foundation

/// Per-test local storage, independent of HOME, WALTER_CONFIG, and preferences.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        // Avoid an environment-supplied TMPDIR that could be network-backed.
        url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("walter-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }
}
