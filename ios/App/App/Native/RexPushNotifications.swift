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

    /// Nov 19 — when we last put the ask in front of this person.
    ///
    /// `hasAsked` above is a permanent flag, and permanent was the bug. One
    /// tap on "Not now" and that device never raised the subject again, for
    /// the life of the install. On 19 November 27 of 55 people had no
    /// notification preferences row at all and not one person had turned push
    /// off deliberately — so the whole gap is people who were asked once at a
    /// bad moment, or never reached the question, and could not be asked
    /// again.
    ///
    /// A date instead, so "Not now" means not now rather than never, and a
    /// week later it comes back. Devices carrying the old permanent flag have
    /// no date, which is why everyone who ever said "Not now" is asked once
    /// more after this ships. That is the intent.
    private static let askedAtKey = "rex.pushAskedAt"

    static var lastAskedAt: Date? {
        get { UserDefaults.standard.object(forKey: askedAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: askedAtKey) }
    }

    /// A week after "not now".
    ///
    /// Started at thirty days and came down on 22 November. Thirty is the
    /// safe number for a settled app and the wrong one during a ramp-up: the
    /// people being asked now joined days ago, and a month of silence is most
    /// of the window in which they decide whether Rex is worth keeping. A
    /// week is long enough to read as a second ask rather than nagging, and
    /// short enough to land while they are still making that decision.
    ///
    /// This is the same dial as the friend-request nudge's cooldown, and the
    /// same caution applies: it is the number to raise again once push is
    /// actually reaching phones, because a prompt that returns too often is
    /// how somebody decides the answer is no for good — and iOS only lets
    /// them say that once.
    private static let askAgainAfter: TimeInterval = 7 * 24 * 60 * 60

    /// Should the ask screen be shown now?
    ///
    /// Two conditions, and the second is the new one. iOS must still be
    /// willing to show its dialog (`canAsk`), and we must not have asked
    /// recently. The denied case deliberately returns false: iOS shows its
    /// permission dialog once per install and no amount of asking from us
    /// brings it back, so those people get the Settings route inside the ask
    /// screen instead of a prompt that cannot work.
    static func shouldAsk() async -> Bool {
        guard await canAsk() else { return false }
        guard let last = lastAskedAt else { return true }
        return Date().timeIntervalSince(last) > askAgainAfter
    }

    /// The free half of the problem: iOS says yes and the server says no.
    ///
    /// send-push only pushes to people with push_enabled true, and that
    /// column defaults to off. Somebody who allowed notifications on a
    /// previous install, or on another account on the same phone, arrives
    /// with iOS permission already granted and no preferences row — so they
    /// get silence, and no prompt would help because there is nothing left
    /// to prompt for.
    ///
    /// Only ever writes when there is NO row. A row saying false is a
    /// decision somebody made on the preferences screen, and quietly
    /// reversing it would be a worse bug than the one this fixes.
    static func reconcilePreferenceIfAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        guard await RexAPI.shared.notificationPreferencesRowExists() == false else { return }
        try? await RexAPI.shared.updateNotificationPreference(["push_enabled": true])
        record("Notifications were already allowed on this phone \u{2014} switched push on.")
    }

    /// Sept 15 — the device token only ever reached the server once: the
    /// moment someone first allowed notifications. If that one save
    /// failed (it always did, until today) or they later signed in on the
    /// same phone, the server never heard about this device again. Asking
    /// iOS for the token on every launch while permission is granted is
    /// Apple's own recommendation — the token can change, and iOS hands the
    /// same one straight back when it hasn't — so it's cheap, and it's what
    /// gets every phone that already said yes registered after this fix.
    static func refreshRegistrationIfAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            record(status == .denied ? "Notifications are turned off for Rex in iOS Settings."
                   : "Rex hasn't asked for notification permission yet.")
            return
        }
        record("Asking Apple for this phone's push address\u{2026}")
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    // MARK: - Diagnostics (15 Sept)

    /// Sept 15 — pushes still weren't arriving after build 41's fix, and the
    /// server showed no registered phones, with nothing on the phone to say
    /// which step was failing: permission, Apple handing over the token, or
    /// saving it. Each step now records what happened; Notification settings
    /// shows the latest, and a failure is reported once so it can be seen
    /// without anyone having to screenshot anything.
    static let statusKey = "rex.pushStatus"

    static var lastStatus: String? { UserDefaults.standard.string(forKey: statusKey) }

    static func record(_ status: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        UserDefaults.standard.set("\(status) (\(stamp))", forKey: statusKey)
    }

    /// Reported at most once per build per phone, via the ordinary feedback
    /// table — the one place the app already writes that the team reads.
    static func reportFailure(_ detail: String) async {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let key = "rex.pushFailureReported.\(build)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? await RexAPI.shared.sendFeedback(
            message: "[push diagnostic, build \(build)] \(detail)", anonymous: false, page: "push-registration"
        )
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
                    RexPushNotifications.lastAskedAt = Date()
                    let granted = await RexPushNotifications.requestPermission()
                    // The server only pushes to people with push switched on
                    // in their preferences (send-push checks push_enabled,
                    // which defaults to off) — saying yes here has to flip it,
                    // or iOS would allow notifications that never get sent.
                    if granted {
                        try? await RexAPI.shared.updateNotificationPreference(["push_enabled": true])
                    }
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
                // Nov 19 — records when, not whether. This used to set the
                // permanent flag, so one tap here ended the conversation for
                // good on this device. Asked again in a week.
                RexPushNotifications.hasAsked = true
                RexPushNotifications.lastAskedAt = Date()
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
