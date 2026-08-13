import SwiftUI

/// v1 scope: search + send request, incoming/outgoing requests, friends list.
/// Skips suggested-friends ranking (a server function, different RPC path than the plain
/// Supabase REST this client speaks), top-friends starring, groups, and invite-sharing.
struct FriendsView: View {
    @State private var friendships: [Friendship] = []
    @State private var profilesById: [String: RexProfileDetail] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var searchQuery = ""
    @State private var searchResults: [RexProfileDetail] = []
    @State private var isSearching = false
    @State private var pendingActionIds = Set<String>()

    private var myId: String? { RexAPI.shared.currentUserId }

    private var incoming: [Friendship] {
        friendships.filter { $0.addressee_id == myId && $0.status == "pending" }
    }
    private var outgoing: [Friendship] {
        friendships.filter { $0.requester_id == myId && $0.status == "pending" }
    }
    private var accepted: [Friendship] {
        friendships.filter { $0.status == "accepted" }
    }

    private func otherProfile(_ f: Friendship) -> RexProfileDetail? {
        let otherId = f.requester_id == myId ? f.addressee_id : f.requester_id
        return profilesById[otherId]
    }

    private func alreadyConnected(_ profileId: String) -> Bool {
        friendships.contains { $0.requester_id == profileId || $0.addressee_id == profileId }
    }

    var body: some View {
        ScrollView {
            TopRexxersView()
                .padding(.horizontal, RexSpacing.page)
                .padding(.top, RexSpacing.sm)
            if isLoading {
                ProgressView().padding(.top, 80)
            } else if let errorMessage {
                errorState(errorMessage)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    searchSection
                    if !searchResults.isEmpty { searchResultsSection }
                    if !incoming.isEmpty { section("Requests for you", rows: incoming.map { .request($0) }) }
                    if !outgoing.isEmpty { section("Pending", rows: outgoing.map { .pending($0) }) }
                    section("Your friends\(accepted.isEmpty ? "" : " (\(accepted.count))")", rows: accepted.map { .friend($0) }, emptyText: "No friends yet. Search above to add someone.")
                }
            }
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await RexAPI.shared.fetchFriendships()
            friendships = fetched
            let ids = Set(fetched.flatMap { [$0.requester_id, $0.addressee_id] })
            let profiles = try await RexAPI.shared.fetchProfiles(ids: Array(ids))
            profilesById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search by username", text: $searchQuery)
                    .padding(12)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
                    .onSubmit { Task { await search() } }

                Button {
                    Task { await search() }
                } label: {
                    if isSearching {
                        ProgressView().tint(RexColor.primaryForeground)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .frame(width: 48, height: 48)
                .background(RexColor.primary)
                .foregroundStyle(RexColor.primaryForeground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(16)
        }
    }

    private func search() async {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        searchResults = (try? await RexAPI.shared.searchProfilesByUsername(q)) ?? []
        isSearching = false
    }

    private var searchResultsSection: some View {
        section("Search results", rows: searchResults.map { .searchResult($0) })
    }

    private enum Row: Identifiable {
        case request(Friendship), pending(Friendship), friend(Friendship), searchResult(RexProfileDetail)
        var id: String {
            switch self {
            case .request(let f), .pending(let f), .friend(let f): return f.id
            case .searchResult(let p): return "search-\(p.id)"
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, rows: [Row], emptyText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RexColor.mutedForeground)
                .padding(.horizontal, 16)

            if rows.isEmpty, let emptyText {
                Text(emptyText)
                    .font(.system(size: 14))
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in rowView(row) }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .request(let f):
            if let profile = otherProfile(f) {
                personRow(profile) {
                    HStack(spacing: 6) {
                        Button {
                            Task { await respond(f, accept: true) }
                        } label: {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                        }
                        .frame(width: 34, height: 34)
                        .background(RexColor.primary)
                        .foregroundStyle(RexColor.primaryForeground)
                        .clipShape(Circle())

                        Button {
                            Task { await respond(f, accept: false) }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        }
                        .frame(width: 34, height: 34)
                        .background(RexColor.card)
                        .foregroundStyle(RexColor.foreground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(RexColor.border, lineWidth: 1))
                    }
                }
            }
        case .pending(let f):
            if let profile = otherProfile(f) {
                personRow(profile) {
                    Text("Waiting…").font(.system(size: 12)).foregroundStyle(RexColor.mutedForeground)
                }
            }
        case .friend(let f):
            if let profile = otherProfile(f) {
                personRow(profile) { EmptyView() }
            }
        case .searchResult(let profile):
            personRow(profile) {
                let connected = alreadyConnected(profile.id)
                let pending = pendingActionIds.contains(profile.id)
                Button {
                    Task { await sendRequest(profile.id) }
                } label: {
                    if pending {
                        ProgressView()
                    } else {
                        Text(connected ? "Sent" : "Add")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(connected ? RexColor.card : RexColor.primary)
                .foregroundStyle(connected ? RexColor.foreground : RexColor.primaryForeground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(RexColor.border, lineWidth: connected ? 1 : 0))
                .disabled(connected || pending)
            }
        }
    }

    @ViewBuilder
    private func personRow<Trailing: View>(_ profile: RexProfileDetail, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            // The name and photo open their profile; the trailing action
            // (accept/reject/add) stays its own tap target outside the link.
            NavigationLink(value: UserProfileRoute(
                userId: profile.id,
                name: profile.display_name ?? profile.username
            )) {
                HStack(spacing: 12) {
                    UserAvatarView(
                        url: profile.avatar_url,
                        name: profile.display_name ?? profile.username,
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.display_name ?? profile.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Text("@\(profile.username)").font(.system(size: 12)).foregroundStyle(RexColor.mutedForeground)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            trailing()
        }
        .padding(12)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(RexColor.border, lineWidth: 1))
    }

    private func sendRequest(_ addresseeId: String) async {
        pendingActionIds.insert(addresseeId)
        do {
            try await RexAPI.shared.sendFriendRequest(addresseeId: addresseeId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingActionIds.remove(addresseeId)
    }

    private func respond(_ f: Friendship, accept: Bool) async {
        do {
            try await RexAPI.shared.respondToFriendRequest(id: f.id, accept: accept)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(.footnote).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.footnote.weight(.semibold)).foregroundStyle(RexColor.primary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}
