import Foundation

enum HistoryRetention {
    static func key(_ kind: LibraryKind) -> String {
        switch kind { case .image: "historyRetentionDays"; case .text: "textHistoryRetentionDays"; case .link: "linkHistoryRetentionDays" }
    }
    static func days(_ kind: LibraryKind, defaults: UserDefaults) -> Int {
        let specific = defaults.integer(forKey: key(kind))
        if ImageHistory.dayChoices.contains(specific) { return specific }
        let legacy = defaults.integer(forKey: "historyRetentionDays")
        return ImageHistory.dayChoices.contains(legacy) ? legacy : 30
    }

    /// Only the newest unsaved copies of each kind stay; older ones are deleted
    /// permanently with the age rule (LibraryStore.prune). Saved items never count.
    static let keepCountKey = "historyKeepCount"
    static let keepCountChoices = [5, 10, 20, 50]
    static let defaultKeepCount = 10
    /// A saved positive choice wins over the default.
    static func keepCount(defaults: UserDefaults) -> Int {
        guard let saved = defaults.object(forKey: keepCountKey) as? Int, saved > 0 else { return defaultKeepCount }
        return saved
    }
}
