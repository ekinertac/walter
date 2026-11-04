import Foundation

/// SwiftPM's generated Bundle.module accessor assumes an unbundled executable
/// on some toolchains. Prefer resources embedded in the installed .app so it
/// remains self-contained after the build directory is deleted.
enum WalterResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Walter_Walter.bundle"),
           let embedded = Bundle(url: url) {
            return embedded
        }
        return Bundle.module // unbundled development builds/tests only
    }()
}
