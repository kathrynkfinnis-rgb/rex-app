import SwiftUI
import Contacts
import CryptoKit

/// Sept 14 — everything for a new person finding the people they know:
/// choosing a username they can be found by, matching their contacts, and
/// browsing a friend's friends. See migration 20260914100000_find_friends.

/// Where invites point until Rex is on the App Store. One constant, so
/// swapping it for the App Store link is a one-line change.
enum RexInvite {
    static let link = URL(string: "https://testflight.apple.com/join/WBkDCpXV")!
    static let message = "I\u{2019}m using Rex to share recommendations with friends \u{2014} places, books, trips, the lot. Join me:"
}

// MARK: - Person row

/// One person with the right button for where you stand with them: Add,
/// Requested, Accept (they've asked you — accepting is on the Friends
/// screen, so this just says so), or Friends.
struct FoundPersonRow: View {
    let person: FoundPerson
    var isBusy: Bool = false
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: UserProfileRoute(userId: person.id, name: person.name)) {
                HStack(spacing: 12) {
                    UserAvatarView(url: person.avatar_url, name: person.name, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(person.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                            .lineLimit(1)
                        Text("@\(person.username)")
                            .font(.system(size: 12))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            trailing
        }
        .padding(12)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(RexColor.border, lineWidth: 1))
    }

    @ViewBuilder
    private var trailing: some View {
        switch person.connection {
        case "you":
            Text("You").font(.system(size: 12)).foregroundStyle(RexColor.mutedForeground)
        case "friend":
            Label("Friends", systemImage: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RexColor.primary)
        case "requested":
            Text("Requested").font(.system(size: 12)).foregroundStyle(RexColor.mutedForeground)
        case "requested_you":
            Text("Asked you").font(.system(size: 12, weight: .semibold)).foregroundStyle(RexColor.accent)
        default:
            Button(action: onAdd) {
                if isBusy {
                    ProgressView().frame(width: 36)
                } else {
                    Text("Add").font(.system(size: 13, weight: .semibold))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RexColor.primary)
            .foregroundStyle(RexColor.primaryForeground)
            .clipShape(Capsule())
            .disabled(isBusy)
        }
    }
}

// MARK: - A friend's friends

struct FriendsOfView: View {
    let userId: String
    let name: String

    @State private var people: [FoundPerson] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyIds: Set<String> = []
    @State private var query = ""

    private var visible: [FoundPerson] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return people }
        return people.filter { $0.name.lowercased().contains(q) || $0.username.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if people.count > 8 {
                    TextField("Search \(name)\u{2019}s friends", text: $query)
                        .padding(12)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
                        .padding(.bottom, 8)
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(RexColor.destructive)
                } else if people.isEmpty {
                    Text("\(name) hasn\u{2019}t added any friends yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    ForEach(visible) { person in
                        FoundPersonRow(person: person, isBusy: busyIds.contains(person.id)) {
                            Task { await add(person) }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("\(name)\u{2019}s friends")
        .navigationBarTitleDisplayMode(.inline)
        .rexDismissableKeyboard()
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            people = try await RexAPI.shared.fetchFriendsOf(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func add(_ person: FoundPerson) async {
        busyIds.insert(person.id)
        do {
            try await RexAPI.shared.sendFriendRequest(addresseeId: person.id)
            if let i = people.firstIndex(where: { $0.id == person.id }) { people[i].connection = "requested" }
        } catch {
            errorMessage = error.localizedDescription
        }
        busyIds.remove(person.id)
    }
}

// MARK: - Contacts

/// "Find friends through contacts". Reads the email addresses in your
/// contacts, hashes each one on the phone (SHA-256 of the lower-cased
/// address), and asks Rex which accounts match. The addresses themselves
/// never leave the phone and nothing is stored.
///
/// Emails rather than phone numbers because that's what Rex accounts have —
/// sign-up doesn't ask for a number. Anyone who isn't on Rex yet is one
/// share-sheet away from an invite.
struct ContactsFriendFinderView: View {
    private enum Stage { case intro, working, denied, done }

    @State private var stage: Stage = .intro
    @State private var matches: [FoundPerson] = []
    @State private var contactCount = 0
    @State private var busyIds: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                switch stage {
                case .intro:
                    intro
                case .working:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking your contacts\u{2026}").font(RexFont.text(14)).foregroundStyle(RexColor.mutedForeground)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                case .denied:
                    denied
                case .done:
                    results
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(RexColor.destructive)
                }

                inviteCard
            }
            .padding(RexSpacing.page)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Find friends")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Already allowed on an earlier visit — go straight to results.
            let status = CNContactStore.authorizationStatus(for: .contacts)
            if stage == .intro, status == .authorized || status == .limited {
                Task { await run() }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(RexColor.primary)
            Text("See who you know on Rex")
                .font(RexFont.display(22, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("We check the email addresses in your contacts against people on Rex. They\u{2019}re scrambled on your phone before anything is sent, and nothing is stored.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
            Button {
                Task { await run() }
            } label: {
                Text("Check my contacts").frame(maxWidth: .infinity)
            }
            .buttonStyle(RexPrimaryButtonStyle())
            .padding(.top, RexSpacing.sm)
        }
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            Text("Rex can\u{2019}t see your contacts")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("To check them, allow access in Settings \u{2192} Apps \u{2192} Rex \u{2192} Contacts. Or search by name on the Friends screen instead.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(RexFont.text(15, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if matches.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                Text("No one yet")
                    .font(RexFont.display(20, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Text(contactCount == 0
                     ? "None of your contacts have an email address saved, so there was nothing to check."
                     : "None of the \(contactCount) email addresses in your contacts are on Rex yet \u{2014} invite a few below.")
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.mutedForeground)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(matches.count) \(matches.count == 1 ? "person" : "people") you know \(matches.count == 1 ? "is" : "are") on Rex".uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
                ForEach(matches) { person in
                    FoundPersonRow(person: person, isBusy: busyIds.contains(person.id)) {
                        Task { await add(person) }
                    }
                }
            }
        }
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text("Invite friends")
                .font(RexFont.display(17, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Send a link by text, WhatsApp or email.")
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)
            ShareLink(item: RexInvite.link, message: Text(RexInvite.message)) {
                Label("Share invite link", systemImage: "square.and.arrow.up")
                    .font(RexFont.text(15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .overlay(RoundedRectangle(cornerRadius: RexRadius.button).stroke(RexColor.primary, lineWidth: 1.5))
            }
            .foregroundStyle(RexColor.primary)
        }
        .padding(RexSpacing.cardPadding)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous).stroke(RexColor.border, lineWidth: 1))
    }

    private func run() async {
        errorMessage = nil
        let store = CNContactStore()
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        guard granted else { stage = .denied; return }
        stage = .working

        let hashes: [String] = await Task.detached(priority: .userInitiated) {
            var out = Set<String>()
            let request = CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor])
            try? store.enumerateContacts(with: request) { contact, _ in
                for labelled in contact.emailAddresses {
                    let email = (labelled.value as String).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard email.contains("@") else { continue }
                    let digest = SHA256.hash(data: Data(email.utf8))
                    out.insert(digest.map { String(format: "%02x", $0) }.joined())
                }
            }
            return Array(out)
        }.value

        contactCount = hashes.count
        do {
            matches = try await RexAPI.shared.matchContactEmails(hashes: hashes)
        } catch {
            errorMessage = error.localizedDescription
        }
        stage = .done
    }

    private func add(_ person: FoundPerson) async {
        busyIds.insert(person.id)
        do {
            try await RexAPI.shared.sendFriendRequest(addresseeId: person.id)
            if let i = matches.firstIndex(where: { $0.id == person.id }) { matches[i].connection = "requested" }
        } catch {
            errorMessage = error.localizedDescription
        }
        busyIds.remove(person.id)
    }
}

// MARK: - Username

/// "When Danny logged in, he wasn't asked to create a username." Shown once
/// to anyone whose username was made up for them at sign-up. It's what
/// friend search looks for, so it's worth thirty seconds of their attention
/// before anything else.
struct UsernameSetupView: View {
    let suggestedUsername: String
    let suggestedName: String?
    var onDone: () -> Void

    @State private var name = ""
    @State private var username = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")

    private var validationMessage: String? {
        if username.count < 3 { return "At least 3 characters." }
        if username.count > 20 { return "20 characters at most." }
        if username.unicodeScalars.contains(where: { !Self.allowed.contains($0) }) {
            return "Letters, numbers and underscores only."
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                Image("RexWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 44)
                    .padding(.top, RexSpacing.xxl)

                VStack(alignment: .leading, spacing: RexSpacing.sm) {
                    Text("How friends find you")
                        .font(RexFont.display(26, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    Text("Pick your name and a username. Friends search for either to add you.")
                        .font(RexFont.text(15))
                        .foregroundStyle(RexColor.mutedForeground)
                }

                VStack(alignment: .leading, spacing: RexSpacing.xs) {
                    Text("Your name").font(RexFont.text(13, weight: .semibold))
                    TextField("e.g. Danny O\u{2019}Gorman", text: $name)
                        .textContentType(.name)
                        .padding(12)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: RexSpacing.xs) {
                    Text("Username").font(RexFont.text(13, weight: .semibold))
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(RexColor.mutedForeground)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .onChange(of: username) { _, new in
                                let cleaned = new.lowercased().replacingOccurrences(of: " ", with: "_")
                                if cleaned != new { username = cleaned }
                            }
                    }
                    .padding(12)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
                    if let validationMessage, !username.isEmpty {
                        Text(validationMessage).font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).font(RexFont.text(13)).foregroundStyle(RexColor.destructive)
                }

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                    } else {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(RexPrimaryButtonStyle())
                .disabled(isSaving || validationMessage != nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(validationMessage == nil && !name.trimmingCharacters(in: .whitespaces).isEmpty ? 1 : 0.5)
            }
            .padding(RexSpacing.page)
        }
        .background(RexColor.background.ignoresSafeArea())
        .rexDismissableKeyboard()
        .interactiveDismissDisabled()
        .onAppear {
            if name.isEmpty { name = suggestedName ?? "" }
            if username.isEmpty { username = Self.looksGenerated(suggestedUsername) ? "" : suggestedUsername }
        }
    }

    /// A hidden Apple email turns into a username like "x7kq2mzr9p" — not
    /// worth pre-filling; an empty box asks the question more honestly.
    private static func looksGenerated(_ username: String) -> Bool {
        let digits = username.filter(\.isNumber).count
        return username.count >= 8 && digits >= 3 && !username.contains("_")
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            try await RexAPI.shared.claimUsername(username, displayName: name)
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
