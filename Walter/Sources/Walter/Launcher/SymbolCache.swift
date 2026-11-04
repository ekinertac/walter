/// Worker-built cache for a finite set of built-in symbol/description pairs.
/// Descriptions remain distinct for accessibility. Missing symbols are cached
/// too. No query text, result models, filesystem data, or persistence lives here.
final class SymbolCache<Image> {
    private struct Key: Hashable {
        let name: String
        let description: String
    }
    private struct Entry { let image: Image? }
    private var entries: [Key: Entry] = [:]
    private let load: (String, String) -> Image?

    init(load: @escaping (String, String) -> Image?) { self.load = load }

    /// Read-only lookup for published snapshots. A miss must NEVER invoke the
    /// loader on the UI thread; later publication can supply a previously absent icon.
    func cachedImage(name: String, description: String) -> Image? {
        entries[Key(name: name, description: description)]?.image
    }

    func image(name: String, description: String) -> Image? {
        let key = Key(name: name, description: description)
        if let cached = entries[key] { return cached.image }
        let image = load(name, description)
        entries[key] = Entry(image: image)
        return image
    }
}
