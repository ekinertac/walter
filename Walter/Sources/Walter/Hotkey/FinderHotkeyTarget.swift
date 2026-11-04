// The sole app-hotkey exception outside the ordinary application roots.
import Foundation

struct FinderHotkeyTarget {
    static let path = "/System/Library/CoreServices/Finder.app"
    private let url: URL

    // Tests supply a synthetic bundle, never the installed Finder or OS state.
    init(url: URL = URL(fileURLWithPath: FinderHotkeyTarget.path, isDirectory: true)) {
        self.url = url
    }

    func validatedURL(for path: String) -> URL? {
        // Exact spelling only: no alternate paths, descendants, or file: URLs.
        guard path == url.path else { return nil }
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        // Reject each redirected component before inspecting anything beneath
        // it, including Contents/Info.plist. Never resolve an outside target.
        var current = ""
        for component in infoURL.path.split(separator: "/") {
            current += "/" + component
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: current)) == nil else { return nil }
        }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
              let info = NSDictionary(contentsOf: infoURL),
              // Finder uses its own package type, not the ordinary APPL type.
              info["CFBundlePackageType"] as? String == "FNDR",
              info["CFBundleIdentifier"] as? String == "com.apple.finder" else { return nil }
        return url
    }
}
