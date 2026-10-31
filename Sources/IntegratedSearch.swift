import Foundation

// Adapter for the unmodified LaunchNext search sources. See THIRD_PARTY_NOTICES.md.
@MainActor final class IntegratedSearch {
    private var entries: [String: SearchIndexEntry] = [:]
    private let matcher = FuzzyMatcher()

    func update(_ apps: [InstalledApp]) {
        var next: [String: SearchIndexEntry] = [:]
        for app in apps {
            for name in [app.name] + app.searchAliases {
                next[name] = entries[name] ?? SearchIndexEntry(displayName: name, prepareTransliteration: true)
            }
        }
        entries = next
    }

    func matching(_ apps: [InstalledApp], query: String) -> [InstalledApp] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return apps }
        let variants = Set([query,
            query.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? query,
            query.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? query])
        return apps.enumerated().compactMap { index, app -> (Int, InstalledApp, SearchMatch)? in
            var best: SearchMatch?
            for name in [app.name] + app.searchAliases {
                guard let entry = entries[name] else { continue }
                for variant in variants {
                    guard let score = matcher.score(query: variant, entry: entry) else { continue }
                    if let previous = best {
                        if score.source.rawValue > previous.source.rawValue ||
                            (score.source.rawValue == previous.source.rawValue && score.score > previous.score) { best = score }
                    } else { best = score }
                }
            }
            guard let match = best else { return nil }
            return (index, app, match)
        }.sorted {
            if $0.2.source.rawValue != $1.2.source.rawValue { return $0.2.source.rawValue > $1.2.source.rawValue }
            if $0.2.score != $1.2.score { return $0.2.score > $1.2.score }
            return $0.0 < $1.0
        }.map { $0.1 }
    }
}
