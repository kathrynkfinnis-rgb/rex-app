import Foundation
import Security

/// Oct 16, security review (F6) — where the session actually lives.
///
/// Both tokens were in UserDefaults, which is an unencrypted plist inside the
/// app container: it lands in unencrypted local backups, it is readable on a
/// jailbroken or forensically imaged handset, and it has no protection class
/// at all. RexAPI's own header had said "move to Keychain before this ships
/// beyond simulator testing" since the first commit. It shipped in June and
/// has been in TestFlight ever since.
///
/// The refresh token is the valuable half. It is long-lived, and until this
/// change signing out did not revoke it server-side (F7), so a copy taken off
/// a backup kept working indefinitely.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is the right class for a
/// session rather than the more obvious WhenUnlocked: the app refreshes tokens
/// from background pushes and from a notification tap before the user has
/// unlocked, and WhenUnlocked would fail those reads. `ThisDeviceOnly` keeps
/// the item out of iCloud Keychain and out of a restored backup, which is the
/// backup problem this is here to solve.
enum RexKeychain {
    /// One generic-password item per key, scoped to this app's bundle.
    private static let service = "com.kathrynfinnis.rexapp.session"

    static func string(_ key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = withUnsafeMutablePointer(to: &item) {
            SecItemCopyMatching(query as CFDictionary, $0)
        }
        query.removeAll()
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes, or deletes when given nil. Delete-then-add rather than
    /// SecItemUpdate: it is one code path instead of two, and the item is
    /// small enough that the extra call costs nothing.
    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)

        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Oct 16 — moves a session that is already on the device.
    ///
    /// Everyone in TestFlight is signed in with tokens in UserDefaults. Without
    /// this they would all be signed out by the upgrade, which is both rude and
    /// the kind of thing that gets reported as a bug. Reads the old value once,
    /// writes it to the Keychain, and clears the plist copy so the plaintext
    /// does not linger in the next backup.
    ///
    /// Safe to call on every launch: once the defaults are empty it does
    /// nothing at all.
    static func migrateFromUserDefaults(keys: [String]) {
        for key in keys {
            guard let legacy = UserDefaults.standard.string(forKey: key) else { continue }
            if string(key) == nil { set(legacy, for: key) }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
