import AppKit
import Foundation

struct InstalledApp: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let url: URL
    let bundleIdentifier: String?
    let categoryIdentifier: String?
    let searchAliases: [String]
    var isSystemApplication: Bool { url.standardizedFileURL.path.hasPrefix("/System/") }
    init(id: String, name: String, url: URL, bundleIdentifier: String?, categoryIdentifier: String? = nil, searchAliases: [String] = []) {
        self.id = id; self.name = name; self.url = url
        self.bundleIdentifier = bundleIdentifier; self.categoryIdentifier = categoryIdentifier
        self.searchAliases = searchAliases
    }
}

struct CatalogSnapshot: Sendable {
    let apps: [InstalledApp]
    let iconVersions: [String: [Date]]
    let isComplete: Bool
    func inventory(retaining knownApps: [InstalledApp]) -> [InstalledApp] {
        guard !isComplete else { return apps }
        let found = Set(apps.map(\.id))
        // Hide unavailable launch paths, but never use this partial list to prune saved layouts.
        return (apps + knownApps.filter { !found.contains($0.id) && FileManager.default.fileExists(atPath: $0.url.path) }).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

}

struct AppCatalog: Sendable {
    static let ownBundleIdentifier = "local.jianqi.SimpleLauncher"
    let roots: [URL]
    let excludedRoots: [URL]
    let excludedBundleIdentifiers: Set<String>
    let preferredLanguages: [String]
    let includeSystemApplications: Bool

    init(
        roots: [URL] = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/Applications", isDirectory: true)
        ],
        excludedRoots: [URL] = [URL(fileURLWithPath: "/System", isDirectory: true)],
        excludedBundleIdentifiers: Set<String> = [ownBundleIdentifier],
        preferredLanguages: [String] = Locale.preferredLanguages,
        includeSystemApplications: Bool = false
    ) {
        self.includeSystemApplications = includeSystemApplications
        self.roots = roots + (includeSystemApplications ? [
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        ] : [])
        self.excludedRoots = includeSystemApplications ? [] : excludedRoots
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.preferredLanguages = preferredLanguages
    }

    func snapshot(preferredLanguages: [String]? = nil) -> CatalogSnapshot {
        let discovery = discover(preferredLanguages: preferredLanguages)
        let inventory = discovery.apps
        let versions = Dictionary(uniqueKeysWithValues: inventory.map { app in
            let dates = [app.url, Self.metadataLocation(for: app.url).info].map {
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            }
            return (app.url.path, dates)
        })
        return CatalogSnapshot(apps: inventory, iconVersions: versions, isComplete: discovery.complete)
    }

    func scan(preferredLanguages: [String]? = nil) -> [InstalledApp] { discover(preferredLanguages: preferredLanguages).apps }
    private func discover(preferredLanguages overrideLanguages: [String]? = nil) -> (apps: [InstalledApp], complete: Bool) {
        var complete = true
        let namingLanguages = overrideLanguages ?? preferredLanguages
        let manager = FileManager.default
        var seenPaths = Set<String>()
        var seenIdentifiers = Set<String>()
        var apps: [InstalledApp] = []

        for root in roots {
            if Task.isCancelled { break }
            guard manager.fileExists(atPath: root.path) else { continue }
            let isApp = root.pathExtension.lowercased() == "app"
            let enumerator = isApp ? nil : manager.enumerator(at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in complete = false; return true })
            let candidates: AnySequence<URL> = isApp ? AnySequence([root]) : AnySequence {
                AnyIterator { enumerator?.nextObject() as? URL }
            }
            for candidate in candidates {
                if Task.isCancelled { break }
                guard candidate.pathExtension.lowercased() == "app" else { continue }
                enumerator?.skipDescendants()
                let url = candidate.resolvingSymlinksInPath().standardizedFileURL
                guard !excludedRoots.contains(where: { Self.contains(url, in: $0) }), !seenPaths.contains(url.path) else { continue }
                let metadata = Self.metadataLocation(for: url)
                guard manager.fileExists(atPath: url.path),
                      let data = try? Data(contentsOf: metadata.info),
                      let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
                else { complete = false; continue }
                if info["CFBundlePackageType"] == nil { complete = false; continue }
                guard
                      ((info["CFBundlePackageType"] as? String) == "APPL"
                       || (includeSystemApplications && url.path == "/System/Library/CoreServices/Finder.app"
                           && (info["CFBundlePackageType"] as? String) == "FNDR"
                           && (info["CFBundleIdentifier"] as? String) == "com.apple.finder")),
                      !Self.boolean(info["LSBackgroundOnly"])
                else { continue }

                let identifier = info["CFBundleIdentifier"] as? String
                if let identifier, !identifier.isEmpty {
                    guard !excludedBundleIdentifiers.contains(identifier),
                          !seenIdentifiers.contains(identifier) else { continue }
                    seenIdentifiers.insert(identifier)
                }
                seenPaths.insert(url.path)
                let localized = localizedMetadata(at: metadata.bundle, preferredLanguages: namingLanguages)
                let name = [
                    localized?["CFBundleDisplayName"] as? String,
                    localized?["CFBundleName"] as? String,
                    info["CFBundleDisplayName"] as? String,
                    info["CFBundleName"] as? String,
                    candidate.deletingPathExtension().lastPathComponent
                ].compactMap { $0 }.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })!
                apps.append(InstalledApp(
                    id: identifier.flatMap { $0.isEmpty ? nil : $0 } ?? url.path,
                    name: name,
                    url: url,
                    bundleIdentifier: identifier,
                    categoryIdentifier: info["LSApplicationCategoryType"] as? String,
                    searchAliases: Array(Set([info["CFBundleDisplayName"] as? String,
                                              info["CFBundleName"] as? String,
                                              candidate.deletingPathExtension().lastPathComponent]
                        .compactMap { $0 }.filter { !$0.isEmpty && $0 != name })).sorted()
                ))
            }
        }
        let sorted = apps.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.url.path < $1.url.path : order == .orderedAscending
        }
        return (sorted, complete && !Task.isCancelled)
    }

    static func matching(_ apps: [InstalledApp], query: String) -> [InstalledApp] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter { app in ([app.name] + app.searchAliases).contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
    }

    private static func metadataLocation(for url: URL) -> (bundle: URL, info: URL) {
        let native = url.appendingPathComponent("Contents/Info.plist")
        if FileManager.default.fileExists(atPath: native.path) { return (url, native) }
        // Apple-silicon iPhone/iPad installations expose their inner .app through WrappedBundle.
        let wrapped = url.appendingPathComponent("WrappedBundle").resolvingSymlinksInPath().standardizedFileURL
        if wrapped.path.hasPrefix(url.standardizedFileURL.path + "/"), wrapped.pathExtension.lowercased() == "app" {
            let flatInfo = wrapped.appendingPathComponent("Info.plist")
            if FileManager.default.fileExists(atPath: flatInfo.path) { return (wrapped, flatInfo) }
        }
        return (url, native)
    }

    private func localizedMetadata(at url: URL, preferredLanguages: [String]) -> [String: Any]? {
        guard let bundle = Bundle(url: url) else { return nil }
        // Modern Apple applications use a binary localization table instead of per-language strings.
        if let resource = bundle.resourceURL?.appendingPathComponent("InfoPlist.loctable"),
           let data = try? Data(contentsOf: resource),
           let table = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] {
            let available = Set(table.keys.map { String($0.split(separator: "~")[0]) })
            let choices = Bundle.preferredLocalizations(from: available.sorted(), forPreferences: preferredLanguages)
            if let language = choices.first {
                var metadata = table[language] as? [String: Any] ?? [:]
                if let mac = table[language + "~mac"] as? [String: Any] { metadata.merge(mac) { _, native in native } }
                if metadata["CFBundleDisplayName"] != nil || metadata["CFBundleName"] != nil { return metadata }
            }
        }
        let languages = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: preferredLanguages)
        if let language = languages.first,
           let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: language),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let metadata = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] {
            return metadata
        }
        return bundle.localizedInfoDictionary
    }

    private static func boolean(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["true", "yes", "1"].contains(string.lowercased()) }
        return false
    }

    private static func contains(_ child: URL, in parent: URL) -> Bool {
        let root = parent.resolvingSymlinksInPath().standardizedFileURL.path
        return child.path == root || child.path.hasPrefix(root + "/")
    }
}

