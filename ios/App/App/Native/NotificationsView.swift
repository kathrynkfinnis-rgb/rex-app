import SwiftUI

struct NotificationsView: View {
    @State private var notifications: [RexNotification] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding(.top, 80)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if notifications.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(notifications) { n in
                        row(n)
                    }
                }
                .padding(16)
            }
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            notifications = try await RexAPI.shared.fetchNotifications()
            let unreadIds = notifications.filter { $0.read_at == nil }.map { $0.id }
            try? await RexAPI.shared.markNotificationsRead(ids: unreadIds)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @ViewBuilder
    private func row(_ n: RexNotification) -> some View {
        let content = HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(RexColor.secondary)
                Text(String((n.actor?.display_name ?? n.actor?.username ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RexColor.secondaryForeground)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(n.copy).font(.system(size: 14)).foregroundStyle(RexColor.foreground).lineLimit(3)
                if let date = ISO8601DateFormatter().date(from: n.created_at) ?? relaxedDate(n.created_at) {
                    Text(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
                        .font(.system(size: 11))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            }
            Spacer()
            if n.read_at == nil {
                Circle().fill(RexColor.primary).frame(width: 8, height: 8).padding(.top, 4)
            }
        }
        .padding(12)
        .background(n.read_at == nil ? RexColor.card : RexColor.card.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(n.read_at == nil ? RexColor.primary.opacity(0.3) : RexColor.border, lineWidth: 1))

        if let itemId = n.linkedItemId {
            NavigationLink(value: itemId) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private func relaxedDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell").font(.system(size: 32)).foregroundStyle(RexColor.mutedForeground)
            Text("You're all caught up").font(.system(size: 17, weight: .semibold)).foregroundStyle(RexColor.foreground)
            Text("When friends comment, like, or send you a blast you'll see it here.")
                .font(.system(size: 13))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
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
