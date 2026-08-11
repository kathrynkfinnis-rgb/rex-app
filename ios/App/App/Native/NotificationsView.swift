import SwiftUI

/// Route marker for notifications that point at the friends screen.
struct FriendsRoute: Hashable {}

struct NotificationsView: View {
    private enum Filter: String, CaseIterable {
        case all = "All"
        case unread = "Unread"
        case social = "Social"
        case activity = "Activity"
    }

    @State private var notifications: [RexNotification] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var filter: Filter = .all

    /// Friend requests/accepts are "social"; likes, comments, saves, mentions
    /// and blasts are "activity" — same split the web uses.
    private func isSocial(_ n: RexNotification) -> Bool {
        n.type.hasPrefix("friend")
    }

    private var visible: [RexNotification] {
        switch filter {
        case .all: return notifications
        case .unread: return notifications.filter { $0.read_at == nil }
        case .social: return notifications.filter(isSocial)
        case .activity: return notifications.filter { !isSocial($0) }
        }
    }

    private var unreadCount: Int {
        notifications.filter { $0.read_at == nil }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                header

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RexRadius.card)
                            .fill(RexColor.muted)
                            .frame(height: 66)
                    }
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if visible.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: RexSpacing.md) {
                        ForEach(visible) { n in row(n) }
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.bottom, RexSpacing.xxl)
        }
        .background(RexColor.background.ignoresSafeArea())
        .refreshable { await load(markRead: false) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") { Task { await markAllRead() } }
                        .font(RexFont.text(13, weight: .semibold))
                        .foregroundStyle(RexColor.primary)
                }
            }
        }
        .task { await load(markRead: false) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: RexSpacing.sm) {
                Text("Notifications")
                    .font(RexFont.display(30, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(RexFont.text(12, weight: .semibold))
                        .foregroundStyle(RexColor.primaryForeground)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 2)
                        .background(RexColor.primary)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: RexSpacing.sm) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button {
                        filter = f
                    } label: {
                        Text(f.rawValue)
                            .font(RexFont.text(13, weight: filter == f ? .semibold : .regular))
                            .foregroundStyle(filter == f ? RexColor.primaryForeground : RexColor.mutedForeground)
                            .padding(.horizontal, RexSpacing.md)
                            .padding(.vertical, 6)
                            .background(filter == f ? RexColor.primary : RexColor.card)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(filter == f ? RexColor.primary : RexColor.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, RexSpacing.sm)
    }

    /// Wraps the row in whichever destination the notification points at:
    /// a trip itinerary, an item, the friends screen, or nothing.
    @ViewBuilder
    private func row(_ n: RexNotification) -> some View {
        if n.isTrip, let recId = n.entity_id {
            NavigationLink(value: TripRoute(recommendationId: recId, title: n.linkedTitle ?? "Trip")) {
                rowContent(n)
            }
            .buttonStyle(.plain)
        } else if let itemId = n.linkedItemId {
            NavigationLink(value: itemId) { rowContent(n) }.buttonStyle(.plain)
        } else if n.linksToFriends {
            NavigationLink(value: FriendsRoute()) { rowContent(n) }.buttonStyle(.plain)
        } else {
            rowContent(n)
        }
    }

    private func rowContent(_ n: RexNotification) -> some View {
        HStack(alignment: .top, spacing: RexSpacing.md) {
            UserAvatarView(
                url: n.actor?.avatar_url,
                name: n.actor?.display_name ?? n.actor?.username ?? "?",
                size: 36
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(n.copy)
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = relaxedDate(n.created_at) ?? ISO8601DateFormatter().date(from: n.created_at) {
                    Text(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
                        .font(RexFont.text(11))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            }

            Spacer(minLength: RexSpacing.sm)

            if n.read_at == nil {
                Circle().fill(RexColor.primary).frame(width: 8, height: 8).padding(.top, 5)
            }
        }
        .padding(RexSpacing.cardPadding)
        .rexCard()
    }

    private func load(markRead: Bool) async {
        isLoading = notifications.isEmpty
        errorMessage = nil
        do {
            notifications = try await RexAPI.shared.fetchNotifications()
            if markRead { await markAllRead() }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Explicit rather than automatic on open — marking everything read the
    /// instant the screen appears means you lose track of what you hadn't seen.
    private func markAllRead() async {
        let unread = notifications.filter { $0.read_at == nil }.map(\.id)
        guard !unread.isEmpty else { return }
        try? await RexAPI.shared.markNotificationsRead(ids: unread)
        notifications = (try? await RexAPI.shared.fetchNotifications()) ?? notifications
    }

    private func relaxedDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private var emptyState: some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "bell")
                .font(.system(size: 30))
                .foregroundStyle(RexColor.mutedForeground)
            Text(filter == .all ? "You're all caught up" : "Nothing here")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("When friends comment, like, or send you a blast you'll see it here.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
        .padding(.top, RexSpacing.xxl)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(RexFont.text(13)).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load(markRead: false) } }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primary)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}
