import SwiftUI

/// v1 scope: the "want to visit/watch/try" list (wants table). Matches the web app's
/// Collections/HitList page conceptually, but skips shared/public collections and any
/// custom-named collections beyond this single built-in want-to list.
struct CollectionsView: View {
    @State private var wants: [WantRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if wants.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(wants) { want in
                            wantRow(want)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Collections")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(RexColor.foreground)
            Text("Everything you want to read, watch, eat and do.")
                .font(.system(size: 13))
                .foregroundStyle(RexColor.mutedForeground)
            if !wants.isEmpty {
                Text("\(wants.count) saved")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(RexColor.primary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            wants = try await RexAPI.shared.fetchWants()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @ViewBuilder
    private func wantRow(_ want: WantRow) -> some View {
        if let item = want.items {
            let category = RexCategory(rawType: item.type)
            NavigationLink(value: item.id) {
                HStack(spacing: 12) {
                    Group {
                        if let urlString = item.image_url, let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    RexColor.muted
                                }
                            }
                        } else {
                            RexColor.muted.overlay(Image(systemName: category.symbol).foregroundStyle(RexColor.mutedForeground))
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 3) {
                            Image(systemName: category.symbol).font(.system(size: 9))
                            Text(category.label.uppercased()).font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(RexColor.primary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RexColor.primary.opacity(0.1))
                        .clipShape(Capsule())

                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                            .lineLimit(1)
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(.system(size: 12)).foregroundStyle(RexColor.mutedForeground).lineLimit(1)
                        }
                        if let date = parseDate(want.created_at) {
                            Text("Saved \(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))")
                                .font(.system(size: 10))
                                .foregroundStyle(RexColor.mutedForeground.opacity(0.8))
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(RexColor.mutedForeground)
                }
                .padding(12)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(RexColor.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await remove(want) }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private func remove(_ want: WantRow) async {
        wants.removeAll { $0.id == want.id }
        try? await RexAPI.shared.deleteWant(id: want.id)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark").font(.system(size: 32)).foregroundStyle(RexColor.mutedForeground)
            Text("Nothing saved yet").font(.system(size: 17, weight: .semibold)).foregroundStyle(RexColor.foreground)
            Text("Tap \"Want to visit/watch/try\" when adding a Rex to save it here.")
                .font(.system(size: 13))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
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
