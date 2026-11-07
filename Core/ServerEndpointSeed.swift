import Foundation

/// A one-time server address supplied at launch (`-seedServerEndpoint ws://host:8787/live`).
///
/// Saved once into the same setting the Connection screen edits, so the user can still change it
/// afterwards. A plain `-serverEndpoint` launch argument cannot do this: it overrides the saved
/// value for the whole launch.
public enum ServerEndpointSeed {
    public static let launchKey = "seedServerEndpoint"
    public static let settingKey = "serverEndpoint"

    /// Saves the seed as the server address. Returns false and changes nothing unless the seed
    /// is a `ws://` or `wss://` address with a host.
    @discardableResult
    public static func apply(_ seed: String?, to defaults: UserDefaults) -> Bool {
        guard let seed = seed?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: seed),
              let scheme = url.scheme?.lowercased(), scheme == "ws" || scheme == "wss",
              let host = url.host, !host.isEmpty else { return false }
        defaults.set(seed, forKey: settingKey)
        return true
    }
}
