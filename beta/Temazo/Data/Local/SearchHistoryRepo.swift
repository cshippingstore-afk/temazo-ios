import Foundation
import Combine

/// Historial de búsquedas recientes — UserDefaults simple, máximo 15 entradas.
@MainActor
final class SearchHistoryRepo: ObservableObject {
    static let shared = SearchHistoryRepo()
    private let key = "temazo_search_history"
    private let max = 15

    @Published private(set) var items: [String] = []

    private init() { items = load() }

    private func load() -> [String] {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        if raw.isEmpty { return [] }
        return raw
            .components(separatedBy: "\u{1F}")
            .filter { !$0.isEmpty }
            .prefix(max)
            .map { String($0) }
    }

    private func save() {
        UserDefaults.standard.set(items.joined(separator: "\u{1F}"), forKey: key)
    }

    func add(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        var updated = [q] + items.filter { $0.lowercased() != q.lowercased() }
        if updated.count > max { updated = Array(updated.prefix(max)) }
        items = updated
        save()
    }

    func remove(_ q: String) {
        items.removeAll { $0 == q }
        save()
    }

    func clearAll() {
        items = []
        save()
    }
}
