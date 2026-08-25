import SwiftUI

struct NotificationPreferencesRoute: Hashable {}

/// #175 — matches the mockup Kathryn approved: a master push toggle, then
/// the same category toggles the web's flat notification-settings page
/// already has, just grouped into sections. Turning push on requests OS
/// permission and registers for a device token (see AppDelegate); turning
/// it off just saves the preference — revoking OS-level permission stays
/// Settings.app's job, same as every other iOS app.
struct NotificationPreferencesView: View {
    @State private var prefs: RexNotificationPreferences?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isRequestingPermission = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.destructive)
                        .padding(.top, 40)
                } else if let prefs {
                    pushRow(prefs)

                    group(title: "Activity on your Rex") {
                        row("heart", "Likes", key: "rec_like", value: prefs.rec_like)
                        row("bubble.left", "Comments", key: "rec_comment", value: prefs.rec_comment)
                        row("person.badge.plus", "Tagged in a Rex", key: "rec_tagged", value: prefs.rec_tagged)
                    }

                    group(title: "Friends") {
                        row("person.badge.plus", "Friend requests", key: "friend_request", value: prefs.friend_request)
                        row("person.crop.circle.badge.checkmark", "Request accepted", key: "friend_accepted", value: prefs.friend_accepted)
                        row(
                            "sparkles", "Friend posts a new Rex", key: "friend_new_rec", value: prefs.friend_new_rec,
                            subtitle: "Off by default — a lot of activity"
                        )
                    }

                    group(title: "Blasts") {
                        row("lightbulb", "New blast from a friend", key: "blast_new", value: prefs.blast_new)
                        row("bubble.left.and.bubble.right", "Blast responses", key: "blast_comment", value: prefs.blast_comment)
                    }
                }
            }
            .padding(RexSpacing.page)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func pushRow(_ prefs: RexNotificationPreferences) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Push notifications").font(RexFont.text(15, weight: .medium)).foregroundStyle(RexColor.foreground)
                Text("On this device").font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
            }
            Spacer()
            if isRequestingPermission {
                ProgressView()
            } else {
                Toggle("", isOn: Binding(
                    get: { prefs.push_enabled },
                    set: { next in Task { await setPushEnabled(next) } }
                ))
                .labelsHidden()
                .tint(RexColor.primary)
            }
        }
        .padding(RexSpacing.md)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous).stroke(RexColor.border, lineWidth: 1))
    }

    @ViewBuilder
    private func group<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text(title.uppercased())
                .font(RexFont.text(12, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(RexColor.mutedForeground)
            VStack(spacing: 0) { content() }
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous).stroke(RexColor.border, lineWidth: 1))
        }
    }

    private func row(_ symbol: String, _ label: String, key: String, value: Bool, subtitle: String? = nil) -> some View {
        HStack(spacing: RexSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(value ? RexColor.primary : RexColor.mutedForeground)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(RexFont.text(14.5)).foregroundStyle(RexColor.foreground)
                if let subtitle {
                    Text(subtitle).font(RexFont.text(11.5)).foregroundStyle(RexColor.mutedForeground)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { value },
                set: { next in Task { await save([key: next]) } }
            ))
            .labelsHidden()
            .tint(RexColor.primary)
        }
        .padding(RexSpacing.md)
        .overlay(alignment: .bottom) {
            Rectangle().fill(RexColor.divider).frame(height: 1).padding(.leading, 44)
        }
    }

    private func load() async {
        isLoading = true
        do {
            prefs = try await RexAPI.shared.fetchNotificationPreferences()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save(_ patch: [String: Bool]) async {
        // Optimistic — flips back on failure rather than leaving the
        // toggle silently out of sync with what's actually saved.
        let previous = prefs
        prefs = applying(patch, to: prefs)
        do {
            try await RexAPI.shared.updateNotificationPreference(patch)
        } catch {
            prefs = previous
            errorMessage = error.localizedDescription
        }
    }

    private func applying(_ patch: [String: Bool], to prefs: RexNotificationPreferences?) -> RexNotificationPreferences? {
        guard var prefs else { return nil }
        for (key, value) in patch {
            switch key {
            case "rec_like": prefs.rec_like = value
            case "rec_comment": prefs.rec_comment = value
            case "rec_tagged": prefs.rec_tagged = value
            case "friend_request": prefs.friend_request = value
            case "friend_accepted": prefs.friend_accepted = value
            case "friend_new_rec": prefs.friend_new_rec = value
            case "blast_new": prefs.blast_new = value
            case "blast_comment": prefs.blast_comment = value
            case "push_enabled": prefs.push_enabled = value
            default: break
            }
        }
        return prefs
    }

    private func setPushEnabled(_ enabled: Bool) async {
        if enabled {
            isRequestingPermission = true
            let granted = await RexPushNotifications.requestPermission()
            isRequestingPermission = false
            guard granted else {
                errorMessage = "Push needs to be allowed in iOS Settings > REX > Notifications first."
                return
            }
        }
        await save(["push_enabled": enabled])
    }
}
