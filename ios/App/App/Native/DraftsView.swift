import SwiftUI

struct DraftsRoute: Hashable {}

/// Your own draft trips — journaled but not yet published. Reached from
/// Profile. Only ever shows your own by construction: RLS hides anyone
/// else's drafts before fetchDraftTrips' query even runs.
struct DraftsView: View {
    @State private var drafts: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var openTrip: TripRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RexRadius.card)
                            .fill(RexColor.muted)
                            .frame(height: 76)
                    }
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if drafts.isEmpty {
                    empty()
                } else {
                    ForEach(drafts) { draft in
                        Button {
                            openTrip = TripRoute(recommendationId: draft.id, title: draft.items?.title ?? "Trip")
                        } label: {
                            row(draft)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.vertical, RexSpacing.lg)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Drafts")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openTrip) { TripDetailView(route: $0) }
        .task { await load() }
    }

    private func row(_ draft: FeedRecommendation) -> some View {
        HStack(spacing: RexSpacing.md) {
            ZStack {
                RexColor.muted
                Image(systemName: "bag").font(.system(size: 18)).foregroundStyle(RexColor.mutedForeground)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.items?.title ?? "Trip")
                    .font(RexFont.text(15, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(1)
                Text("Draft — started \(relativeDate(draft.created_at))")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            Spacer(minLength: RexSpacing.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .padding(RexSpacing.cardPadding)
        .rexCard()
    }

    private func relativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            drafts = try await RexAPI.shared.fetchDraftTrips()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func empty() -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "doc.text").font(.system(size: 28)).foregroundStyle(RexColor.mutedForeground)
            Text("No drafts")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Start a trip and save it as a draft to journal stops as you go, then publish the whole thing when you're ready.")
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
            Button("Retry") { Task { await load() } }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primary)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}
