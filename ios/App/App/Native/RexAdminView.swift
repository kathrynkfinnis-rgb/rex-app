import SwiftUI

struct RexAdminRoute: Hashable {}

/// Oct 19 — "we should split out the admin queue to post and the feedback
/// into two separate links from the Settings page." Two jobs that were one
/// screen: deciding what REX says, and reading what people tell you. They
/// are done at different times and in different frames of mind, and the
/// queue being empty is not a reason to stop looking at the feedback.
struct RexFeedbackRoute: Hashable {}

/// Oct 18 — "Rex is uploading recipes with no content — please stop uploading
/// anything at the moment, but is there a way that you can suggest stuff and
/// we can choose to post or not?" And then: "is that where I'd see the
/// feedback too?"
///
/// Both, in one place, on the phone.
///
/// The queue needed no new machinery. A post by the REX account with no
/// `published_at` is already exactly a suggestion — that state has existed
/// since 18 September, it was simply drained by a timer every fifteen minutes
/// with nobody looking at it first. This is the looking.
///
/// The feedback half answers the other question. The ! button in the app has
/// written to `public.feedback` since 30 July and nothing ever read it back,
/// so months of it sat unseen. The website admin page reads it now too; this
/// is the same thing where you already are.
struct RexAdminView: View {
    @State private var queue: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var busyId: String?
    @State private var confirmingDiscard: FeedRecommendation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.destructive)
                        .padding(.horizontal, RexSpacing.page)
                }

                queueSection
            }
            .padding(.vertical, RexSpacing.lg)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Waiting to post")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .alert(
            "Discard this?",
            isPresented: Binding(
                get: { confirmingDiscard != nil },
                set: { if !$0 { confirmingDiscard = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { confirmingDiscard = nil }
            Button("Discard", role: .destructive) {
                if let rec = confirmingDiscard { Task { await discard(rec) } }
            }
        } message: {
            Text("It won't be posted, and it won't come back.")
        }
    }

    // MARK: - Waiting to post

    @ViewBuilder
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            header("Waiting to post", count: queue.count)

            if isLoading && queue.isEmpty {
                ProgressView().padding(.horizontal, RexSpacing.page)
            } else if queue.isEmpty {
                empty("Nothing queued. Anything REX writes lands here first, and goes out only when you say so.")
            } else {
                ForEach(queue) { rec in
                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        // The card as it will actually appear, which is the
                        // whole point of reviewing on the phone rather than
                        // reading a row in a table.
                        RecommendationCardView(rec: rec)

                        if let scheduled = rec.scheduled_at, !scheduled.isEmpty {
                            Label(scheduledLine(scheduled), systemImage: "clock")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }

                        HStack(spacing: RexSpacing.sm) {
                            Button {
                                Task { await publish(rec) }
                            } label: {
                                if busyId == rec.id {
                                    ProgressView().tint(RexColor.primaryForeground)
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Post it").fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 42)
                            .background(RexColor.primary)
                            .foregroundStyle(RexColor.primaryForeground)
                            .clipShape(Capsule())
                            .disabled(busyId != nil)

                            Button(role: .destructive) {
                                confirmingDiscard = rec
                            } label: {
                                Text("Discard").fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .frame(height: 42)
                            .foregroundStyle(RexColor.destructive)
                            .overlay(Capsule().stroke(RexColor.border, lineWidth: 1))
                            .disabled(busyId != nil)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, RexSpacing.page)
                }
            }
        }
    }

    /// "Scheduled for 21 Oct, 09:00", or nothing if the stamp won't parse.
    private func scheduledLine(_ raw: String) -> String {
        guard let date = ISO8601DateFormatter.rexDate(from: raw) else { return "Scheduled" }
        return "Scheduled for " + date.formatted(.dateTime.day().month().hour().minute())
    }

    // MARK: - Chrome

    private func header(_ title: String, count: Int) -> some View {
        HStack(spacing: RexSpacing.sm) {
            Text(title)
                .font(RexFont.display(19, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            if count > 0 {
                Text("\(count)")
                    .font(RexFont.text(12, weight: .semibold))
                    .foregroundStyle(RexColor.badgeForeground)
                    .padding(.horizontal, RexSpacing.sm)
                    .padding(.vertical, 3)
                    .background(RexColor.badgeBackground)
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, RexSpacing.page)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(RexFont.text(13))
            .foregroundStyle(RexColor.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, RexSpacing.page)
    }

    // MARK: - Work

    private func load() async {
        errorMessage = nil
        queue = await RexAPI.shared.fetchOfficialQueue()
        isLoading = false
    }

    private func publish(_ rec: FeedRecommendation) async {
        busyId = rec.id
        defer { busyId = nil }
        do {
            try await RexAPI.shared.publishQueuedPost(id: rec.id)
            queue.removeAll { $0.id == rec.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discard(_ rec: FeedRecommendation) async {
        confirmingDiscard = nil
        busyId = rec.id
        defer { busyId = nil }
        do {
            try await RexAPI.shared.deleteRecommendation(id: rec.id)
            queue.removeAll { $0.id == rec.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
