import UIKit
import UserNotifications

/// #175 — thin wrapper around UNUserNotificationCenter + UIApplication's
/// remote-notification registration. Kept separate from RexAPI (which is
/// the Supabase HTTP layer) since this talks to iOS, not the network.
enum RexPushNotifications {
    /// Sept 15 — "I never got a request for you to turn notifications on,
    /// which is a key retention tool" (Danny). The only way in was a toggle
    /// in notification settings. Now new accounts are asked at the end of
    /// onboarding, and existing accounts that were never asked get asked
    /// once. This flag is what makes it "once": iOS only shows its own
    /// dialog one time, so our screen shouldn't keep reappearing either.
    static let askedKey = "rex.pushPrompted"

    static var hasAsked: Bool {
        get { UserDefaults.standard.bool(forKey: askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedKey) }
    }

    /// True only while iOS hasn't been asked yet — after that, the answer
    /// lives in Settings and a second prompt from us would be pointless.
    static func canAsk() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
    }

    /// Requests OS permission and, if granted, kicks off APNs registration.
    /// The actual device token arrives asynchronously via AppDelegate's
    /// didRegisterForRemoteNotificationsWithDeviceToken — this function
    /// only reports whether it's worth waiting for that.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
            return granted
        } catch {
            return false
        }
    }
}


import SwiftUI

/// The ask itself: what notifications are for, then iOS's own dialog. A
/// screen of our own first because the system dialog can only be shown once,
/// and it's much more likely to be accepted when it arrives with a reason.
struct NotificationsAskView: View {
    var onDone: () -> Void
    @State private var isAsking = false

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.lg) {
            Spacer(minLength: RexSpacing.xxl)
            Image(systemName: "bell.badge")
                .font(.system(size: 40))
                .foregroundStyle(RexColor.primary)
            Text("Know when friends reply")
                .font(RexFont.display(26, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            VStack(alignment: .leading, spacing: RexSpacing.md) {
                row("person.badge.plus", "Friend requests, and when someone accepts yours")
                row("bubble.left", "Likes and comments on your Rex")
                row("sparkles", "When a friend answers your blast")
            }
            Text("You can change what you get anytime in Settings.")
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)
            Spacer()
            Button {
                Task {
                    isAsking = true
                    RexPushNotifications.hasAsked = true
                    await RexPushNotifications.requestPermission()
                    isAsking = false
                    onDone()
                }
            } label: {
                if isAsking {
                    ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                } else {
                    Text("Turn on notifications").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(RexPrimaryButtonStyle())
            .disabled(isAsking)
            Button("Not now") {
                RexPushNotifications.hasAsked = true
                onDone()
            }
            .font(RexFont.text(15, weight: .semibold))
            .foregroundStyle(RexColor.mutedForeground)
            .frame(maxWidth: .infinity)
            .padding(.bottom, RexSpacing.lg)
        }
        .padding(.horizontal, RexSpacing.page)
        .background(RexColor.background.ignoresSafeArea())
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: RexSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(RexColor.primary)
                .frame(width: 22)
            Text(text)
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
