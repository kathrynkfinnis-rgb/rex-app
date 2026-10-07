import SwiftUI

/// Route marker for the places-with-no-pin screen.
struct PlacesWithoutPinRoute: Hashable {}

/// Oct 7 — "two matches look right, nothing else identified. Can we do this
/// manually in the app?"
///
/// Editing a place has always been able to set its location: pick an address
/// and the coordinates come with it. What was missing was any way to find the
/// places that need it. Nearly two hundred of them, scattered through lists
/// and trips, with nothing on any screen to say which ones were missing.
///
/// locate-places.mjs could only ever fix a fraction — it searches around a
/// place's siblings, so a place with no located siblings has nothing to search
/// around, and 154 of these have none. It deliberately guesses at nothing. A
/// person looking at the name usually knows exactly where it is, so this makes
/// that the easy path rather than the impossible one.
struct PlacesWithoutPinView: View {
    @State private var items: [RexItem] = []
    @State private var isLoading = true
    /// Oct 7 — "can we make the 198 with no pin only available to admins?"
    /// Checked here as well as on the chip that leads here: a gate that only
    /// exists on the door you came through isn't a gate.
    @State private var isAdmin = false
    @State private var locating: RexItem?
    @State private var fixedIds: Set<String> = []
    @State private var errorMessage: String?

    private var remaining: [RexItem] {
        items.filter { !fixedIds.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.md) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, RexSpacing.xxl)
                } else if !isAdmin {
                    notForYou
                } else if remaining.isEmpty {
                    emptyState
                } else {
                    Text("\(remaining.count) \(remaining.count == 1 ? "place has" : "places have") no pin, so they're missing from the map. Tap one and pick it from the search to put it on there.")
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    if !fixedIds.isEmpty {
                        Label("\(fixedIds.count) located this session", systemImage: "checkmark.circle.fill")
                            .font(RexFont.text(12, weight: .semibold))
                            .foregroundStyle(RexColor.primary)
                    }

                    VStack(spacing: 0) {
                        ForEach(remaining, id: \.id) { item in
                            row(item)
                            if item.id != remaining.last?.id {
                                Divider().padding(.leading, RexSpacing.md)
                            }
                        }
                    }
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                            .stroke(RexColor.border, lineWidth: 1)
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.destructive)
                }
            }
            .padding(RexSpacing.page)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Places with no pin")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $locating) { item in
            RepickItemSheet(
                category: RexCategory(rawType: item.type),
                currentTitle: item.title,
                blurb: "Where is \u{201C}\(item.title)\u{201D}? Pick it from the search and it goes on the map. Nothing else about it changes.",
                heading: "Find this place"
            ) { hit in
                await locate(item, with: hit)
            }
        }
        .task { await load() }
    }

    private func row(_ item: RexItem) -> some View {
        Button {
            locating = item
        } label: {
            HStack(spacing: RexSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(RexFont.text(14.5, weight: .medium))
                        .foregroundStyle(RexColor.foreground)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    // An address with no coordinates is the common case — the
                    // text was typed or imported and never resolved. Showing it
                    // saves you remembering which Soho one this was.
                    if let where_ = item.address ?? item.subtitle, !where_.isEmpty {
                        Text(where_)
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "mappin.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(RexColor.placeholder)
            }
            .padding(RexSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Deliberately plain rather than apologetic. Nobody arrives here by
    /// accident, and anyone who does has lost nothing.
    private var notForYou: some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "lock")
                .font(.system(size: 30))
                .foregroundStyle(RexColor.mutedForeground)
            Text("Not available")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("This one's for the REX team.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(RexSpacing.xxl)
    }

    private var emptyState: some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 30))
                .foregroundStyle(RexColor.mutedForeground)
            Text(fixedIds.isEmpty ? "Everywhere has a pin" : "That's all of them")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Every place and event is on the map.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(RexSpacing.xxl)
    }

    private func load() async {
        isLoading = true
        isAdmin = await RexAPI.shared.isAdmin()
        items = isAdmin ? await RexAPI.shared.fetchPlacesWithoutPin() : []
        isLoading = false
    }

    /// Takes the coordinates and the address from the chosen result, and
    /// nothing else — the title is what people wrote and what they'll
    /// recognise, so Google's spelling of it doesn't get to overrule theirs.
    private func locate(_ item: RexItem, with hit: RexSearchHit) async {
        guard let lat = hit.lat, let lng = hit.lng else {
            errorMessage = "That result had no location on it. Try another."
            return
        }
        do {
            try await RexAPI.shared.updateItemAddressAndCoords(
                itemId: item.id,
                address: hit.address ?? item.address,
                lat: lat,
                lng: lng
            )
            fixedIds.insert(item.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
