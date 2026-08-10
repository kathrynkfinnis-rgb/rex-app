import SwiftUI

/// Collections has three parts, matching the web /me page and the requested
/// split: things you've saved from other people, your own curated lists, and
/// the want-to list.
struct CollectionsView: View {
    private enum Tab: String, CaseIterable {
        case saved = "Saved"
        case lists = "My lists"
        case wants = "Want to"
    }

    @State private var tab: Tab = .saved
    @State private var saved: [SavedPost] = []
    @State private var lists: [RexList] = []
    @State private var wants: [WantRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            RexColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    header

                    if isLoading {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: RexRadius.card)
                                .fill(RexColor.muted)
                                .frame(height: 90)
                        }
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else {
                        switch tab {
                        case .saved: savedSection
                        case .lists: listsSection
                        case .wants: wantsSection
                        }
                    }
                }
                .padding(.horizontal, RexSpacing.page)
                .padding(.bottom, RexSpacing.xxxl)
            }
            .refreshable { await load() }
        }
        // The big editorial heading is in the scroll content, so the nav bar
        // stays empty rather than repeating it.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            Text("Collections")
                .font(RexFont.display(32, weight: .semibold))
                .foregroundStyle(RexColor.foreground)

            Text("Everything you've saved, curated and want to get to.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)

            HStack(spacing: RexSpacing.sm) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        Text("\(t.rawValue)\(countSuffix(for: t))")
                            .font(RexFont.text(13, weight: tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? RexColor.primaryForeground : RexColor.mutedForeground)
                            .padding(.horizontal, RexSpacing.md)
                            .padding(.vertical, 7)
                            .background(tab == t ? RexColor.primary : RexColor.card)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(tab == t ? RexColor.primary : RexColor.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, RexSpacing.sm)
    }

    private func countSuffix(for t: Tab) -> String {
        let n: Int
        switch t {
        case .saved: n = saved.count
        case .lists: n = lists.count
        case .wants: n = wants.count
        }
        return n > 0 ? " \(n)" : ""
    }

    // MARK: - Sections

    @ViewBuilder
    private var savedSection: some View {
        if saved.isEmpty {
            empty("Nothing saved yet", "Tap the bookmark on any Rex to keep it here.")
        } else {
            LazyVStack(spacing: RexSpacing.betweenCards) {
                ForEach(saved) { post in
                    if let rec = post.recommendations {
                        NavigationLink(value: rec.item_id) {
                            RecommendationCardView(rec: rec)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var listsSection: some View {
        if lists.isEmpty {
            empty("No lists yet", "Create a list on the web app — e.g. \u{201C}Baby Recs\u{201D} — and it'll show up here.")
        } else {
            LazyVStack(spacing: RexSpacing.md) {
                ForEach(lists) { list in
                    HStack(spacing: RexSpacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .fill(RexColor.badgeBackground)
                            Text(list.emoji ?? "\u{1F4D2}").font(.system(size: 20))
                        }
                        .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name)
                                .font(RexFont.display(17, weight: .semibold))
                                .foregroundStyle(RexColor.foreground)
                            if let type = list.item_type, !type.isEmpty {
                                Text(RexCategory(rawType: type).label)
                                    .font(RexFont.text(12))
                                    .foregroundStyle(RexColor.mutedForeground)
                            }
                        }
                        Spacer()
                        if list.visibility == "public" {
                            Text("Public")
                                .font(RexFont.text(11, weight: .medium))
                                .foregroundStyle(RexColor.badgeForeground)
                                .padding(.horizontal, RexSpacing.sm)
                                .padding(.vertical, 3)
                                .background(RexColor.badgeBackground)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(RexSpacing.cardPadding)
                    .rexCard()
                }
            }
        }
    }

    @ViewBuilder
    private var wantsSection: some View {
        if wants.isEmpty {
            empty("Nothing on your want-to list", "Add something with \u{201C}Want to try\u{201D} when you post a Rex.")
        } else {
            LazyVStack(spacing: RexSpacing.md) {
                ForEach(wants) { want in
                    if let item = want.items {
                        NavigationLink(value: item.id) {
                            HStack(spacing: RexSpacing.md) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                        .fill(RexColor.muted)
                                    Image(systemName: RexCategory(rawType: item.type).symbol)
                                        .foregroundStyle(RexColor.mutedForeground)
                                }
                                .frame(width: 46, height: 46)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(RexFont.display(17, weight: .semibold))
                                        .foregroundStyle(RexColor.foreground)
                                        .lineLimit(1)
                                    Text(RexCategory(rawType: item.type).label)
                                        .font(RexFont.text(12))
                                        .foregroundStyle(RexColor.mutedForeground)
                                }
                                Spacer()
                            }
                            .padding(RexSpacing.cardPadding)
                            .rexCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func empty(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: RexSpacing.sm) {
            Text(title)
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text(subtitle)
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        isLoading = saved.isEmpty && lists.isEmpty && wants.isEmpty
        errorMessage = nil
        do {
            async let s = RexAPI.shared.fetchSavedPosts()
            async let l = RexAPI.shared.fetchLists()
            async let w = RexAPI.shared.fetchWants()
            let (fetchedSaved, fetchedLists, fetchedWants) = try await (s, l, w)
            saved = fetchedSaved
            lists = fetchedLists
            wants = fetchedWants
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
