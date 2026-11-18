import Foundation
public struct SearchIndex: Sendable {
    private let documents: [(AppRecord, String, String, String)]
    public init(records: [AppRecord]) {
        documents = records.map { app in
            let name = Self.fold(app.label)
            let latin = Self.fold(app.label.applyingTransform(.toLatin, reverse: false) ?? app.label)
            let initials = latin.split(separator: " ").compactMap(\.first).map(String.init).joined()
            return (app, name, latin.replacingOccurrences(of: " ", with: ""), initials)
        }
    }
    public static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    public func search(_ query: String, order: [UUID]) -> [UUID] {
        let q = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines)); guard !q.isEmpty else { return [] }
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return documents.compactMap { app, name, latin, initials -> (UUID, Int, Int)? in
            guard let position = positions[app.id] else { return nil }
            let rank: Int
            if name == q { rank = 0 } else if name.hasPrefix(q) { rank = 1 }
            else if name.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { rank = 2 }
            else if name.contains(q) { rank = 3 }
            else if Self.fold(app.name + " " + app.bundleName + " " + (app.alternateNames ?? []).joined(separator: " ") + " " + (app.bundleID ?? "") + " " + URL(fileURLWithPath: app.path).lastPathComponent).contains(q) { rank = 4 }
            else if latin.contains(q) || initials.hasPrefix(q) { rank = 5 } else { return nil }
            return (app.id, rank, position)
        }.sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
    }
}
