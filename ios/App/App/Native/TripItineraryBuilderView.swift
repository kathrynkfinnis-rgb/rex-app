import SwiftUI
import UniformTypeIdentifiers

/// Sept 2 trips rebuild — the itinerary section of "Add a trip".
///
/// Replaces TripStopsBuilderView for trips (that view still serves Lists,
/// whose items genuinely are a flat list). Three things this does that the
/// old one couldn't:
///
///   - Headings are their own rows, added by their own button, so one can
///     exist before any stop sits under it and can be dragged as a unit.
///   - "Add a heading" and "Add a stop" both sit at the bottom and stay
///     there after every add, so you keep going until you're ready to post
///     rather than the form closing itself off after one.
///   - Rows drag to reorder, including dragging a stop under a different
///     heading — which is just "move it below that heading row", since
///     grouping is positional now (see ItineraryEntry).
///
/// The stop count that used to head this section is gone, per the brief.
struct TripItineraryBuilderView: View {
    @Binding var entries: [ItineraryEntry]

    /// Sept 5 — Lists reuse this whole builder ("update the list inputs so
    /// it's similar to trip input — headings and items in draggable boxes").
    /// The structure is identical; what differs is the wording and which
    /// sheet an entry opens, since a list item is a much shorter form than
    /// a trip stop (no sub-category, rating or note — see ListItemSheet).
    enum Mode { case trip, list }
    var mode: Mode = .trip

    private var noun: String { mode == .trip ? "stop" : "item" }
    private var container: String { mode == .trip ? "trip" : "list" }

    /// Fires when a stop row is tapped, so the host can open the same
    /// editing sheet the "Add a stop" button uses — "if you click on each
    /// rex, should take you to the same style of 'add a stop' [sheet] as in
    /// the manual add a trip process".
    var onEditStop: ((ItineraryEntry) -> Void)? = nil

    @State private var showingAddStop = false
    @State private var renamingHeadingId: UUID?
    @State private var headingDraft = ""
    @State private var draggingId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text(mode == .trip ? "Itinerary" : "Items")
                .font(RexFont.text(14, weight: .semibold))
                .foregroundStyle(RexColor.foreground)

            ForEach(entries) { entry in
                row(for: entry)
                    .opacity(draggingId == entry.id ? 0.4 : 1)
                    .onDrag {
                        draggingId = entry.id
                        return NSItemProvider(object: entry.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: ReorderDropDelegate(
                            target: entry,
                            entries: $entries,
                            draggingId: $draggingId
                        )
                    )
            }

            // Both buttons live here, below everything, and reappear after
            // every add — the "these keep coming up until you are ready to
            // submit" loop from the brief.
            Button {
                headingDraft = ""
                renamingHeadingId = nil
                addHeading()
            } label: {
                Label(
                    entries.contains(where: { $0.headingText != nil })
                        ? "Add another heading (optional)"
                        : (mode == .trip
                           ? "Add a heading e.g. 'Restaurants' or 'Day 1'"
                           : "Add a heading e.g. 'Under \u{00A3}20' or 'Books'"),
                    systemImage: "plus"
                )
                .font(RexFont.text(13.5, weight: .semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DashedAddButtonStyle())

            Button {
                showingAddStop = true
            } label: {
                Label("Add \(noun == "stop" ? "a stop" : "an item")", systemImage: "plus")
                    .font(RexFont.text(13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DashedAddButtonStyle())

            if entries.count > 1 {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle").font(.system(size: 10))
                    Text("Press and hold to drag \(noun == "stop" ? "a stop" : "an item") or heading into a new position.")
                }
                .font(RexFont.text(11.5))
                .foregroundStyle(RexColor.mutedForeground)
            }

            Text("Each \(noun) becomes its own Rex as well as part of the \(container) \u{2014} only the \(container) itself shows on the feed.")
                .font(RexFont.text(11.5))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .sheet(isPresented: $showingAddStop) {
            if mode == .trip {
                TripStopSheet(subcategories: rexSubcategories[.place] ?? []) { stop in
                    entries.append(ItineraryEntry(kind: .stop(stop)))
                }
            } else {
                ListItemSheet { item in
                    entries.append(ItineraryEntry(kind: .stop(item)))
                }
            }
        }
        .alert("Heading", isPresented: Binding(
            get: { renamingHeadingId != nil },
            set: { if !$0 { renamingHeadingId = nil } }
        )) {
            TextField("e.g. Day 1, or Restaurants", text: $headingDraft)
            Button("Cancel", role: .cancel) { renamingHeadingId = nil }
            Button("Save") { commitHeading() }
        }
    }

    @ViewBuilder
    private func row(for entry: ItineraryEntry) -> some View {
        switch entry.kind {
        case .heading(let text):
            HStack(spacing: RexSpacing.sm) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                    .foregroundStyle(RexColor.placeholder)
                Text(text.isEmpty ? "Untitled heading" : text)
                    .font(RexFont.display(15, weight: .semibold))
                    .foregroundStyle(text.isEmpty ? RexColor.placeholder : RexColor.foreground)
                Spacer(minLength: RexSpacing.sm)
                Button {
                    headingDraft = text
                    renamingHeadingId = entry.id
                } label: {
                    Image(systemName: "pencil").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(RexColor.mutedForeground)
                Button(role: .destructive) {
                    entries.removeAll { $0.id == entry.id }
                } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(RexColor.mutedForeground)
            }
            .padding(.horizontal, RexSpacing.md)
            .padding(.vertical, RexSpacing.sm + 2)
            .background(RexColor.secondary)
            .overlay(alignment: .leading) {
                Rectangle().fill(RexColor.gold).frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))

        case .stop(let stop):
            Button {
                onEditStop?(entry)
            } label: {
                HStack(spacing: RexSpacing.sm) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12))
                        .foregroundStyle(RexColor.placeholder)
                    thumbnail(for: stop)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.title)
                            .font(RexFont.text(14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                            .lineLimit(1)
                        if let sub = stop.genre ?? stop.address, !sub.isEmpty {
                            Text(sub)
                                .font(RexFont.text(11.5))
                                .foregroundStyle(RexColor.mutedForeground)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: RexSpacing.sm)
                    if stop.rating > 0 {
                        RexRatingBadge(raw: stop.rating, compact: true)
                    }
                    Button(role: .destructive) {
                        entries.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RexColor.mutedForeground)
                }
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, RexSpacing.sm)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                        .stroke(RexColor.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func thumbnail(for stop: DraftStop) -> some View {
        Group {
            if let urlString = stop.photoURL ?? stop.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RexColor.muted
                    }
                }
            } else {
                RexColor.muted.overlay(
                    Image(systemName: stop.type.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(RexColor.mutedForeground)
                )
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func addHeading() {
        let new = ItineraryEntry(kind: .heading(""))
        entries.append(new)
        headingDraft = ""
        renamingHeadingId = new.id
    }

    private func commitHeading() {
        guard let id = renamingHeadingId,
              let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = headingDraft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // An abandoned "Add a heading" shouldn't leave a blank row behind.
            entries.remove(at: index)
        } else {
            entries[index].kind = .heading(trimmed)
        }
        renamingHeadingId = nil
    }
}

/// Sept 5 — opens a posted trip in the Add-a-trip form from anywhere that
/// only has the trip's own Rex row to hand (the feed's edit pencil, the
/// profile's), which is most places. AddRexView needs the trip's stops too,
/// and those take a fetch, so this holds the spinner while that happens
/// rather than making every call site do it.
struct TripEditorLoader: View {
    let trip: FeedRecommendation
    var onDone: () -> Void

    @State private var stops: [FeedRecommendation]?
    @State private var failed = false

    var body: some View {
        Group {
            if let stops {
                AddRexView(onDone: onDone, editingTrip: trip, stops: stops)
            } else if failed {
                VStack(spacing: RexSpacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(RexColor.destructive)
                    Text("Couldn't open that trip for editing.")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                    Button("Close", action: onDone)
                        .buttonStyle(RexSecondaryButtonStyle())
                        .padding(.horizontal, RexSpacing.xxl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RexColor.background.ignoresSafeArea())
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RexColor.background.ignoresSafeArea())
            }
        }
        .task {
            guard stops == nil else { return }
            if let loaded = try? await RexAPI.shared.fetchTripStops(tripRecommendationId: trip.id) {
                stops = loaded
            } else {
                failed = true
            }
        }
    }
}

/// Moves the dragged row to wherever it's hovering, live, so the list
/// reorders under your finger rather than only on drop.
private struct ReorderDropDelegate: DropDelegate {
    let target: ItineraryEntry
    @Binding var entries: [ItineraryEntry]
    @Binding var draggingId: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingId, draggingId != target.id,
              let from = entries.firstIndex(where: { $0.id == draggingId }),
              let to = entries.firstIndex(where: { $0.id == target.id })
        else { return }
        withAnimation(.snappy) {
            let moved = entries.remove(at: from)
            entries.insert(moved, at: to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }
}

/// The dashed "+ Add …" affordance both buttons share.
private struct DashedAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RexColor.primary)
            .padding(.vertical, 12)
            .padding(.horizontal, RexSpacing.md)
            .background(configuration.isPressed ? RexColor.secondary : RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .strokeBorder(RexColor.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
    }
}
