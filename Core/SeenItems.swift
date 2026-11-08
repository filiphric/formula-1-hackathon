import Foundation

/// Remembers which list items the user has already had the chance to see, so a page icon can show
/// a red dot when something new arrived.
///
/// Whatever is in the list when it is first observed counts as seen: joining a session late, or
/// opening a finished one, should not light every icon. After that, an item is "new" until the
/// user has the page in front of them.
public struct SeenItems: Sendable, Equatable {
    private var seen: Set<String>?

    public init() {}

    /// Feed the current list. The first call sets the baseline; later calls mark items as seen only
    /// while the page is on screen.
    public mutating func observe(_ ids: [String], viewing: Bool) {
        if seen == nil {
            seen = Set(ids)
        } else if viewing {
            seen?.formUnion(ids)
        }
    }

    /// True when the list holds an item that arrived after the baseline and has not been viewed.
    public func hasUnseen(in ids: [String]) -> Bool {
        guard let seen else { return false }
        return ids.contains { !seen.contains($0) }
    }

    /// Forget everything, for example when a different session starts and its list is a fresh one.
    public mutating func reset() { seen = nil }
}
