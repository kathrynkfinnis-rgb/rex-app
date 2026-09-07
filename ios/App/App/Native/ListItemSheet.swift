import SwiftUI

/// Sept 5 — the "Add an item" sheet for Lists.
///
/// Deliberately much shorter than the trip's stop sheet. Kathryn's spec:
/// "remove filter, heading, rating & why are you rexing it. Remove photo but
/// allow option to add a photo to thumbnail" — plus a product link. A list
/// item is usually a thing you'd buy or read rather than somewhere you went,
/// so a sub-category filter, a rating and a note are all boxes nobody fills
/// in; a name, a link and a picture are the whole job.
///
/// What it keeps from the stop sheet: the name field searches your own Rex
/// as well as the wider catalogues, so adding something you've already Rex'd
/// reuses that item rather than duplicating it.
struct ListItemSheet: View {
    /// Which catalogues to search. A list holds anything, so this is the
    /// category the search runs against — Other casts the widest net.
    var searchCategory: RexCategory = .other
    var existing: DraftStop? = nil
    var onSave: (DraftStop) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var picked: RexSearchHit?
    @State private var title = ""
    @State private var linkURL = ""
    @State private var photoURLs: [String] = []

    @State private var myHits: [RexSearchHit] = []
    @State private var webHits: [RexSearchHit] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    field("Name") {
                        TextField("Search or type a name", text: $title)
                            .textFieldStyle(.plain)
                            .onChange(of: title) { _, _ in scheduleSearch() }
                    }
                    searchResults

                    field("Product link") {
                        TextField("https://…", text: $linkURL)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    Text("Filled in automatically when you pick a search result that has one.")
                        .font(RexFont.text(11.5))
                        .foregroundStyle(RexColor.mutedForeground)

                    VStack(alignment: .leading, spacing: RexSpacing.xs) {
                        Text("Thumbnail").font(RexFont.text(13, weight: .semibold))
                        PhotoPickerView(photoURLs: $photoURLs, maxPhotos: 1)
                    }

                    Button {
                        save()
                    } label: {
                        Text(existing == nil ? "Add item" : "Save item").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle(existing == nil ? "New item" : "Edit item")
            .rexDismissableKeyboard()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
        .onAppear(perform: prefill)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.xs) {
            Text(label).font(RexFont.text(13, weight: .semibold)).foregroundStyle(RexColor.foreground)
            content()
                .padding(11)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                        .stroke(RexColor.border, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if picked == nil, !myHits.isEmpty || !webHits.isEmpty {
            VStack(spacing: 0) {
                if !myHits.isEmpty {
                    resultHeader("Your Rex")
                    ForEach(myHits) { hit in resultRow(hit, mine: true) }
                }
                if !webHits.isEmpty {
                    resultHeader("Search results")
                    ForEach(webHits) { hit in resultRow(hit, mine: false) }
                }
            }
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )
        } else if isSearching {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching…").font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
            }
        }
    }

    private func resultHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(RexColor.badgeForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RexSpacing.md)
            .padding(.vertical, 6)
            .background(RexColor.secondary)
    }

    private func resultRow(_ hit: RexSearchHit, mine: Bool) -> some View {
        Button {
            apply(hit)
        } label: {
            HStack(spacing: RexSpacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.title)
                        .font(RexFont.text(13.5, weight: .medium))
                        .foregroundStyle(RexColor.foreground)
                        .lineLimit(1)
                    if let sub = hit.subtitle ?? hit.address, !sub.isEmpty {
                        Text(sub)
                            .font(RexFont.text(11.5))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: RexSpacing.sm)
                if mine {
                    Text("Already Rex'd")
                        .font(RexFont.text(10, weight: .semibold))
                        .foregroundStyle(RexColor.badgeForeground)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RexColor.badgeBackground)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, RexSpacing.md)
            .padding(.vertical, RexSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(RexColor.divider).frame(height: 1) }
    }

    private func prefill() {
        guard let existing, title.isEmpty else { return }
        title = existing.title
        linkURL = existing.linkURL ?? ""
        photoURLs = [existing.photoURL ?? existing.imageURL].compactMap { $0 }
    }

    private func scheduleSearch() {
        picked = nil
        searchTask?.cancel()
        let q = title.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { myHits = []; webHits = []; isSearching = false; return }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            async let mine = (try? await RexAPI.shared.searchMyRexItems(query: q)) ?? []
            async let web = RexSearch.search(category: searchCategory, query: q)
            let (m, w) = await (mine, web)
            guard !Task.isCancelled else { return }
            myHits = m
            let mineTitles = Set(m.map { $0.title.lowercased() })
            webHits = w.filter { !mineTitles.contains($0.title.lowercased()) }.prefix(6).map { $0 }
            isSearching = false
        }
    }

    private func apply(_ hit: RexSearchHit) {
        picked = hit
        title = hit.title
        // "…or this is done automatically": a catalogue result that carries
        // its own product page fills the link in for you.
        if let url = hit.productURL, linkURL.isEmpty { linkURL = url }
        myHits = []
        webHits = []
        isSearching = false
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedLink = linkURL.trimmingCharacters(in: .whitespaces)
        let stop = DraftStop(
            type: picked.map { _ in searchCategory } ?? searchCategory,
            title: trimmedTitle,
            subtitle: picked?.subtitle,
            address: nil,
            lat: nil,
            lng: nil,
            genre: picked?.genre,
            imageURL: picked?.imageURL,
            externalId: picked?.externalSource == "rex" ? nil : picked?.externalId,
            externalSource: picked?.externalSource == "rex" ? nil : picked?.externalSource,
            // No rating and no note by design — see this view's own doc.
            rating: 0,
            note: "",
            section: existing?.section,
            photoURL: photoURLs.first,
            linkURL: trimmedLink.isEmpty ? nil : trimmedLink
        )
        onSave(stop)
        dismiss()
    }
}
