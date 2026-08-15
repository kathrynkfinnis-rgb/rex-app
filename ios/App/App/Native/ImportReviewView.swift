import SwiftUI

/// Where extracted-but-unreviewed items land — nothing here is a real Rex
/// yet. Select which ones to keep, then save the selection as either a Trip
/// (each item becomes a stop under the heading it was extracted with) or a
/// Collection (optionally one per heading). Deselected rows are deleted, not
/// just hidden, so re-opening this screen doesn't resurrect things already
/// dismissed.
struct ImportReviewView: View {
    let source: String
    var onDone: () -> Void

    @State private var rows: [ImportStagingRow] = []
    @State private var isLoading = true
    @State private var selectedIds: Set<String> = []
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var destination: Destination = .collection
    @State private var destinationName = ""
    @State private var splitBySection = false
    @State private var isSaving = false

    private enum Destination: String, CaseIterable { case collection = "Collection", trip = "Trip" }

    private var hasSections: Bool { rows.contains { $0.raw_section != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if rows.isEmpty {
                    Text("Nothing left to review.")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    Text("\(selectedIds.count) of \(rows.count) selected")
                        .font(RexFont.text(13, weight: .medium))
                        .foregroundStyle(RexColor.mutedForeground)

                    ForEach(rows) { row in
                        rowCard(row)
                    }

                    destinationPicker

                    if let errorMessage {
                        Text(errorMessage).font(RexFont.text(13)).foregroundStyle(RexColor.destructive)
                    }
                    if let resultMessage {
                        Text(resultMessage).font(RexFont.text(13, weight: .medium)).foregroundStyle(RexColor.primary)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                        } else {
                            Text("Save \(selectedIds.count) as \(destination.rawValue)").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(isSaving || selectedIds.isEmpty || destinationName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.bottom, RexSpacing.xxl)
                }
            }
            .padding(RexSpacing.page)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func rowCard(_ row: ImportStagingRow) -> some View {
        let selected = selectedIds.contains(row.id)
        return Button {
            if selected { selectedIds.remove(row.id) } else { selectedIds.insert(row.id) }
        } label: {
            HStack(alignment: .top, spacing: RexSpacing.md) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? RexColor.primary : RexColor.border)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let type = row.suggested_type, let category = RexCategory(rawValue: type) {
                            Text(category.label.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(RexColor.badgeForeground)
                                .padding(.horizontal, RexSpacing.sm)
                                .padding(.vertical, 2)
                                .background(RexColor.badgeBackground)
                                .clipShape(Capsule())
                        }
                        if let section = row.raw_section, !section.isEmpty {
                            Text(section)
                                .font(RexFont.text(11, weight: .medium))
                                .foregroundStyle(RexColor.primary)
                        }
                    }

                    Text(row.raw_title)
                        .font(RexFont.text(15, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)

                    if let creator = row.raw_creator, !creator.isEmpty {
                        Text(creator)
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                    }

                    // The whole reason this exists as a review step rather
                    // than posting straight through — the note is exactly
                    // what "must not lose the commentary" meant.
                    if let note = row.raw_note, !note.isEmpty {
                        Text("\u{201C}\(note)\u{201D}")
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.foreground.opacity(0.85))
                            .lineLimit(4)
                    }

                    if let url = row.raw_url, !url.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "link").font(.system(size: 10))
                            Text(url).font(RexFont.text(11)).lineLimit(1)
                        }
                        .foregroundStyle(RexColor.primary)
                    }
                }
            }
            .padding(RexSpacing.cardPadding)
            .rexCard()
            .opacity(selected ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text("Save as").font(RexFont.text(14, weight: .semibold)).foregroundStyle(RexColor.foreground)

            Picker("", selection: $destination) {
                ForEach(Destination.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            TextField(
                destination == .trip ? "Trip name, e.g. \u{201C}Lisbon, 3 days\u{201D}" : "Collection name",
                text: $destinationName
            )
            .font(RexFont.text(15))
            .padding(.horizontal, RexSpacing.md)
            .frame(height: 46)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )

            // Trips already section their stops (raw_section becomes
            // trip_section on every stop) — this toggle only makes sense
            // for Collections, where it's a real choice rather than the
            // default behavior.
            if destination == .collection && hasSections {
                Toggle("Split into a collection per heading", isOn: $splitBySection)
                    .font(RexFont.text(13))
                    .tint(RexColor.primary)
            }
        }
        .padding(.top, RexSpacing.sm)
    }

    private func load() async {
        isLoading = true
        rows = (try? await RexAPI.shared.fetchStagingRows(source: source)) ?? []
        selectedIds = Set(rows.map(\.id))
        isLoading = false
        // Best-effort match against the app's own catalogues (OpenLibrary,
        // TMDB, Google Places), quietly in the background — approving still
        // works even if a row never resolves, it just creates a plain
        // unlinked item the way manual entry always has.
        for row in rows {
            Task { try? await RexAPI.shared.resolveStagingRow(row) }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        resultMessage = nil
        let selectedRows = rows.filter { selectedIds.contains($0.id) }
        let deselectedIds = rows.map(\.id).filter { !selectedIds.contains($0) }
        do {
            if destination == .trip {
                let result = try await RexAPI.shared.approveStagingAsTrip(
                    rows: selectedRows, tripName: destinationName, note: nil
                )
                resultMessage = result.failed.isEmpty
                    ? "Added \(result.added) stops to \u{201C}\(destinationName)\u{201D}."
                    : "Added \(result.added) of \(selectedRows.count) \u{2014} \(result.failed.count) couldn't be saved."
            } else {
                let result = try await RexAPI.shared.approveStagingAsCollections(
                    rows: selectedRows, name: destinationName, splitBySection: splitBySection
                )
                resultMessage = result.failed.isEmpty
                    ? "Saved \(result.added) into \(result.collections == 1 ? "\u{201C}\(destinationName)\u{201D}" : "\(result.collections) collections")."
                    : "Saved \(result.added) of \(selectedRows.count) \u{2014} \(result.failed.count) couldn't be saved."
            }
            try? await RexAPI.shared.deleteStagingRows(ids: deselectedIds)
            // Long enough to actually read the result before the sheet closes.
            try? await Task.sleep(for: .seconds(1.4))
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
