import Foundation

/// Oct 13 — "users should also be able to unpin a blast."
///
/// Which blasts this person has taken off the top of their own feed.
///
/// Kept on the device rather than in the database, which is the unusual call
/// here and worth saying why. Dismissing a blast is a statement about this
/// reader at this moment — not now, not me, I have nothing for this one — and
/// nobody else ever needs to know it. It changes no shared fact: the blast is
/// still live, still answerable, and still in everyone else's feed exactly as
/// it was.
///
/// The cost is that dismissing on the phone doesn't dismiss on the iPad. That
/// would matter for something long-lived; a pin expires after 48 hours anyway,
/// so the worst case is seeing one blast at the top of a second device for
/// less than two days. A table, its RLS, a migration and a round trip on every
/// feed load is a lot of machinery to buy that back.
///
/// Ids are pruned once there are more than a few hundred, oldest first. They
/// are 36-byte strings and a blast stops mattering after two days, so this is
/// about never letting a preferences file grow without bound rather than about
/// saving space.
enum BlastPinStore {
    private static let key = "rex.dismissedBlastIds"
    private static let cap = 300

    static func dismissed() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func dismiss(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !ids.contains(id) else { return }
        ids.append(id)
        if ids.count > cap { ids.removeFirst(ids.count - cap) }
        UserDefaults.standard.set(ids, forKey: key)
    }
}
