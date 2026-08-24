import SwiftUI

/// #162 — "went here with Phoebe": a row of tappable friend chips used both
/// when posting a Rex and when editing one. Kept as a standalone component
/// (rather than inlined in AddRexView/EditRexView) since both need the
/// exact same picker.
struct FriendTagPickerView: View {
    @Binding var selectedIds: Set<String>

    @State private var friends: [RexProfileDetail] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            } else if friends.isEmpty {
                Text("Add friends to tag them on a Rex.")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        ForEach(friends) { friend in
                            chip(friend)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task { await load() }
    }

    private func chip(_ friend: RexProfileDetail) -> some View {
        let isSelected = selectedIds.contains(friend.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected { selectedIds.remove(friend.id) } else { selectedIds.insert(friend.id) }
            }
        } label: {
            HStack(spacing: 6) {
                UserAvatarView(url: friend.avatar_url, name: friend.display_name ?? friend.username, size: 22)
                Text(friend.display_name ?? friend.username)
                    .font(RexFont.text(13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, RexSpacing.sm)
            .padding(.vertical, 6)
            .background(isSelected ? RexColor.primary : RexColor.muted)
            .foregroundStyle(isSelected ? .white : RexColor.foreground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        let fetched = (try? await RexAPI.shared.fetchAcceptedFriendProfiles()) ?? []
        friends = fetched.sorted { ($0.display_name ?? $0.username).localizedCaseInsensitiveCompare($1.display_name ?? $1.username) == .orderedAscending }
        isLoading = false
    }
}

/// Small read-only strip shown on a card/detail page for whoever's tagged —
/// "with Phoebe" rather than a tappable picker.
struct TaggedFriendsRow: View {
    let friends: [RexProfileDetail]
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        if !friends.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "at")
                    .font(.system(size: 11))
                    .foregroundStyle(RexColor.mutedForeground)
                Text("with " + friends.map { $0.display_name ?? $0.username }.joined(separator: ", "))
                    .font(RexFont.text(12, weight: .medium))
                    .foregroundStyle(RexColor.mutedForeground)
                    .lineLimit(1)
            }
        }
    }
}
