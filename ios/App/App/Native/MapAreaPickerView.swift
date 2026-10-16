import SwiftUI
import MapKit

/// Oct 16 — "I want to be able to press the location in the top left and
/// select a place to find Rex", and before that "can we make it so that you
/// can change this place if you're looking for REX in a specific town /
/// village / part of London?"
///
/// The map has always centred on where you are, which is right for "what's
/// near me" and useless for the other half of what a map of recommendations
/// is for: you are planning. You are going to Margate on Saturday, or you
/// want to know what anybody has said about Stoke Newington.
///
/// Apple's geocoder rather than Google Places, deliberately: this searches for
/// an *area*, not a business, it is free, it needs no key, and the map it
/// moves is already MapKit's.
///
/// MKLocalSearchCompleter with `resultTypes = .address` specifically, and not
/// the more obvious MKLocalSearch. MKLocalSearch is a point-of-interest
/// search — typing "Margate" into it returned Le Margat, a restaurant in
/// Brittany, and no Margate at all. `.address` is the completer Apple Maps
/// uses for its own search field, and it ranks towns, villages and
/// neighbourhoods first, which is the entire list anyone wants here.
struct MapAreaPickerView: View {
    /// Where the map is now, so Hackney beats Hackney, Ontario.
    var near: CLLocationCoordinate2D?
    var onPick: (MapArea) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = AreaCompleter()
    @State private var query = ""
    @State private var isResolving = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RexInlineSearchField(placeholder: "Town, village or area\u{2026}", text: $query)
                    .focused($fieldFocused)
                    .padding(.horizontal, RexSpacing.page)
                    .padding(.top, RexSpacing.sm)
                    .padding(.bottom, RexSpacing.md)

                if completer.suggestions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(completer.suggestions, id: \.self) { suggestion in
                                Button {
                                    Task { await choose(suggestion) }
                                } label: {
                                    row(suggestion)
                                }
                                .buttonStyle(.plain)
                                .disabled(isResolving)
                                Divider().overlay(RexColor.divider)
                                    .padding(.leading, RexSpacing.page)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isResolving {
                    // Picking costs one network call to turn the suggestion
                    // into coordinates, which is usually instant and
                    // occasionally isn't.
                    ProgressView()
                        .padding(RexSpacing.lg)
                        .background(RexColor.card, in: RoundedRectangle(cornerRadius: RexRadius.card))
                }
            }
        }
        .tint(RexColor.primary)
        .onAppear {
            fieldFocused = true
            completer.near = near
        }
        .onChange(of: query) { _, text in completer.query = text }
    }

    @ViewBuilder
    private func row(_ suggestion: MKLocalSearchCompletion) -> some View {
        HStack(spacing: RexSpacing.md) {
            Image(systemName: "mappin.circle")
                .font(.system(size: 18))
                .foregroundStyle(RexColor.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(RexFont.text(15, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                    .multilineTextAlignment(.leading)
                if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                        .font(RexFont.text(12.5))
                        .foregroundStyle(RexColor.mutedForeground)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, RexSpacing.page)
        .padding(.vertical, RexSpacing.md)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.trimmingCharacters(in: .whitespaces).count >= 2 {
            Text("Nothing found for \u{201C}\(query)\u{201D}.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .padding(.top, RexSpacing.xl)
        } else {
            // The one thing worth saying before they've typed: what this is
            // for. A blank sheet with a search box doesn't.
            VStack(spacing: RexSpacing.sm) {
                Image(systemName: "map")
                    .font(.system(size: 26))
                    .foregroundStyle(RexColor.primary)
                Text("Look somewhere else")
                    .font(RexFont.display(19, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Text("Going somewhere? Search a town or an area to see what your friends have Rex'd there.")
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, RexSpacing.xxl)
            .padding(.top, RexSpacing.xl)
        }
    }

    /// A completion is a label, not a location — it has to be run through a
    /// search to get coordinates out of it.
    private func choose(_ suggestion: MKLocalSearchCompletion) async {
        isResolving = true
        defer { isResolving = false }
        let request = MKLocalSearch.Request(completion: suggestion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first,
              CLLocationCoordinate2DIsValid(item.placemark.coordinate) else { return }
        onPick(MapArea(
            name: suggestion.title,
            detail: suggestion.subtitle.isEmpty ? nil : suggestion.subtitle,
            coordinate: item.placemark.coordinate
        ))
        dismiss()
    }
}

/// Wraps MKLocalSearchCompleter, whose delegate callbacks predate async/await
/// and arrive on the main thread.
@MainActor
final class AreaCompleter: NSObject, ObservableObject {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []

    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else {
                suggestions = []
                // Also clear the completer itself, or its next callback
                // repopulates the list we just emptied.
                completer.queryFragment = ""
                return
            }
            completer.queryFragment = trimmed
        }
    }

    /// Biased, not restricted — a wide span, so searching a town at the other
    /// end of the country still finds it while local results come first.
    var near: CLLocationCoordinate2D? {
        didSet {
            guard let near, CLLocationCoordinate2DIsValid(near) else { return }
            completer.region = MKCoordinateRegion(
                center: near,
                span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
            )
        }
    }

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Towns, villages and neighbourhoods — not restaurants. See the
        // view's note on why this matters.
        completer.resultTypes = .address
    }
}

extension AreaCompleter: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // A failure here is nearly always "you typed another character before
        // the last lookup finished", which is not worth saying anything about.
        Task { @MainActor in self.suggestions = [] }
    }
}

/// Somewhere the map can be sent.
struct MapArea: Identifiable {
    let name: String
    let detail: String?
    let coordinate: CLLocationCoordinate2D

    var id: String { "\(name)-\(coordinate.latitude)-\(coordinate.longitude)" }
}

/// A request to move the camera. The token makes picking the same place twice
/// two distinct requests, so choosing Margate, panning to Dover, and choosing
/// Margate again goes back to Margate rather than doing nothing.
///
/// CLLocationCoordinate2D isn't Equatable, which is the other reason this
/// carries the two doubles itself.
struct MapRecentre: Equatable {
    let latitude: Double
    let longitude: Double
    let token: Int
}
