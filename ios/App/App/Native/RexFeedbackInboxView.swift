import SwiftUI

/// Oct 19 — "We should split out the admin queue to post and the feedback
/// into two separate links from the Settings page. On the feedback page we
/// should have the ability to X a feedback if we've dealt with it — only
/// Kathryn should have that ability."
///
/// This is the feedback half, lifted out of RexAdminView. The two were one
/// screen because they arrived in the same conversation on 18 October, not
/// because they belong together: one is deciding what REX says, the other is
/// reading what people say to you. An empty queue is no reason to stop
/// reading the second.
///
/// Dealt-with is `status` on the feedback table, which has existed with a
/// default of 'new' since 30 July and which nothing has ever written to. So
/// clearing something needed no new column — only a policy naming who may,
/// which is what actually enforces "only Kathryn". The flag on the profile
/// decides whether the button is drawn; the policy decides whether it works.
struct RexFeedbackInboxView: View {
    @State private var feedback: [RexFeedbackEntry] = []
    @State private var isLoading = true
    @State private var isOwner = false
    @State private var errorMessage: String?
    @State private var busyId: String?
    /// Cleared feedback is hidden by default and still reachable — "dealt
    /// with" is not "never happened", and a list you cannot look back at is
    /// one you stop trusting.
    @State private var showingHandled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.destructive)
                        .padding(.horizontal, RexSpacing.page)
                }

                if isLoading && feedback.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if outstanding.isEmpty && !showingHandled {
                    empty(handled.isEmpty
                          ? "Nothing sent yet. This is the ! button in the app \u{2014} TestFlight reports live in App Store Connect."
                          : "All caught up. Nothing outstanding.")
                } else {
                    list(showingHandled ? handled : outstanding)
                }

                if !handled.isEmpty {
                    Button {
                        showingHandled.toggle()
                    } label: {
                        Text(showingHandled
                             ? "Back to outstanding (\(outstanding.count))"
                             : "Show \(handled.count) already dealt with")
                            .font(RexFont.text(13, weight: .semibold))
                            .foregroundStyle(RexColor.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, RexSpacing.page)
                    .padding(.top, RexSpacing.sm)
                }

                if !diagnostics.isEmpty && !showingHandled {
                    Text("\(diagnostics.count) push diagnostic\(diagnostics.count == 1 ? "" : "s") hidden \u{2014} the app logs those here too.")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                        .padding(.horizontal, RexSpacing.page)
                        .padding(.top, RexSpacing.xs)
                }
            }
            .padding(.vertical, RexSpacing.lg)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(showingHandled ? "Dealt with" : "Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func list(_ entries: [RexFeedbackEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: RexSpacing.sm) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.meta)
                            .font(RexFont.text(11.5))
                            .foregroundStyle(RexColor.mutedForeground)
                        Text(entry.message)
                            .font(RexFont.text(14))
                            .foregroundStyle(entry.isHandled ? RexColor.mutedForeground : RexColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isOwner {
                        Button {
                            Task { await setHandled(entry, !entry.isHandled) }
                        } label: {
                            if busyId == entry.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: entry.isHandled ? "arrow.uturn.backward" : "xmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(RexColor.mutedForeground)
                                    .frame(width: 28, height: 28)
                                    .background(RexColor.muted)
                                    .clipShape(Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(busyId != nil)
                        .accessibilityLabel(entry.isHandled ? "Put back" : "Mark as dealt with")
                    }
                }
                .padding(.horizontal, RexSpacing.page)
                .padding(.vertical, RexSpacing.md)
                Divider().overlay(RexColor.divider)
                    .padding(.leading, RexSpacing.page)
            }
        }
    }

    /// What a person actually wrote, and hasn't been cleared.
    private var written: [RexFeedbackEntry] { feedback.filter { !$0.isDiagnostic } }
    private var outstanding: [RexFeedbackEntry] { written.filter { !$0.isHandled } }
    private var handled: [RexFeedbackEntry] { written.filter(\.isHandled) }
    private var diagnostics: [RexFeedbackEntry] { feedback.filter(\.isDiagnostic) }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(RexFont.text(13))
            .foregroundStyle(RexColor.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, RexSpacing.page)
    }

    private func load() async {
        errorMessage = nil
        async let sent = RexAPI.shared.fetchAppFeedback()
        async let owner = RexAPI.shared.isOwner()
        feedback = await sent
        isOwner = await owner
        isLoading = false
    }

    private func setHandled(_ entry: RexFeedbackEntry, _ handled: Bool) async {
        busyId = entry.id
        defer { busyId = nil }
        do {
            try await RexAPI.shared.setFeedbackHandled(id: entry.id, handled: handled)
            if let index = feedback.firstIndex(where: { $0.id == entry.id }) {
                feedback[index] = RexFeedbackEntry(
                    id: entry.id,
                    message: entry.message,
                    meta: entry.meta,
                    isDiagnostic: entry.isDiagnostic,
                    isHandled: handled
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One line someone sent through the app's feedback button.
struct RexFeedbackEntry: Identifiable {
    let id: String
    let message: String
    let meta: String
    /// Oct 18 — the table carries automated push-registration diagnostics as
    /// well as what people type, and there are far more of the former. Mixed
    /// together they bury the thing worth reading: the first screen of this
    /// list was eight push failures and one real sentence.
    let isDiagnostic: Bool
    /// `status` on the feedback table: 'done' once somebody has dealt with it.
    let isHandled: Bool
}
