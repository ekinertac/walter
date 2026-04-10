// LauncherEngine.swift — Core search and launch logic
//
// Combines three result sources:
//   1. App search (fuzzy matched, frecency-boosted)
//   2. Web search fallback (when no/few app results match)
//
// Fuzzy matching: "vsc" finds "Visual Studio Code", "ff" finds "Firefox".
// Frecency: apps you launch often and recently rank higher.
// Web fallback: always shown as the last result — Enter opens the default browser.
//
// Called by: LauncherPanelController on every keystroke.

import AppKit

struct SearchResult {
    let title: String
    let subtitle: String
    let icon: NSImage?
    let action: ResultAction
}

enum ResultAction {
    case open(String)
    case shell(String)
    case copy(String)
    case url(String)
}

class LauncherEngine {

    private let appIndex: AppIndex
    private let frecency = FrecencyTracker()
    private let calculator = Calculator()
    private let converter = Converter()

    init(onIndexChanged: @escaping () -> Void = {}) {
        appIndex = AppIndex(onChange: onIndexChanged)
    }

    func search(query: String) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return [] }

        var results: [SearchResult] = []

        // Calculator — shown first if the query looks like math
        if let calc = calculator.evaluate(query: q) {
            let icon = NSImage(systemSymbolName: "equal.circle", accessibilityDescription: "Calculator")
            results.append(SearchResult(
                title: calc.answer,
                subtitle: "\(calc.expression) — Enter to copy",
                icon: icon,
                action: .copy(calc.answer)
            ))
        }

        // Currency / unit conversion
        let conversions = converter.convert(query: q)
        if !conversions.isEmpty {
            let icon = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Convert")
            results += conversions.map { conv in
                SearchResult(
                    title: conv.title,
                    subtitle: "\(conv.subtitle) — Enter to copy",
                    icon: icon,
                    action: .copy(conv.copyValue)
                )
            }
        }

        // Fuzzy match all apps, score and rank
        var scored: [(entry: AppEntry, score: Double)] = []

        for entry in appIndex.allEntries {
            let result = fuzzyMatch(query: q, target: entry.name)
            guard result.matched else { continue }

            // Combine fuzzy score with frecency boost
            let frecencyBoost = frecency.score(for: entry.path) * 10
            let total = Double(result.score) + frecencyBoost
            scored.append((entry, total))
        }

        // Sort by combined score descending
        scored.sort { $0.score > $1.score }

        results += scored.prefix(20).map { item -> SearchResult in
            SearchResult(
                title: item.entry.name,
                subtitle: item.entry.path,
                icon: item.entry.icon,
                action: .open(item.entry.path)
            )
        }

        // Web search fallback — always appended as the last option
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let webURL = "https://www.google.com/search?q=\(encoded)"
        let webIcon = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "Web search")
        results.append(SearchResult(
            title: "Search Google for \"\(q)\"",
            subtitle: "Open in default browser",
            icon: webIcon,
            action: .url(webURL)
        ))

        return results
    }

    /// Executes a result action and records frecency for app launches.
    func launch(result: SearchResult) {
        switch result.action {
        case .open(let path):
            frecency.recordLaunch(path: path)
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .url(let urlString):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case .shell(let command):
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", command]
            try? task.run()
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
