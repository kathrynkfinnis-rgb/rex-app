import SwiftUI

/// v1 scope: category picker → manual entry form → post.
/// Skips live external search (Google/TMDB/etc — those are our own server functions over a
/// different RPC protocol, not plain Supabase REST) and skips Trips (needs the stops builder).
/// "Enter details manually" is exactly the fallback path the web app already offers, so this
/// is a real, working subset of Add a Rex rather than a stub.
struct AddRexView: View {
    var onDone: () -> Void

    // Trip sits second, as on the web. A trip is created as a normal Rex here
    // and stops get added to it afterwards from the trip screen.
    private let creatableCategories: [RexCategory] = [.place, .trip, .book, .movie, .tv, .podcast, .recipe, .event, .other]

    private enum Mode { case rated, want }

    @State private var category: RexCategory?
    @State private var mode: Mode = .rated
    @State private var title = ""
    @State private var subtitle = ""
    @State private var address = ""
    @State private var rating: Double = 10
    @State private var note = ""
    @State private var isSaving = false
    @State private var anonymous = false
    @State private var errorMessage: String?
    @State private var didPost = false
    @State private var didWant = false

    // Search-as-you-type against the external catalogues.
    @State private var hits: [RexSearchHit] = []
    @State private var isSearching = false
    @State private var picked: RexSearchHit?
    @State private var searchTask: Task<Void, Never>?
    @State private var photoURLs: [String] = []
    @State private var subcategories: Set<String> = []
    @State private var productLink = ""
    @State private var tripStops: [DraftStop] = []
    @State private var recipeText = ""
    /// Searchable categories open on a search field; the full form only
    /// appears once something's picked or you choose to type it in manually.
    @State private var manualEntry = false

    var body: some View {
        NavigationStack {
            ZStack {
                RexColor.background.ignoresSafeArea()
                ScrollView {
                    if didPost {
                        successState
                    } else if let category {
                        form(for: category)
                    } else {
                        categoryPicker
                    }
                }
            }
            .navigationTitle(category == nil ? "What are you Rexing?" : "Add a \(category!.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if category != nil && !didPost {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            withAnimation {
                                category = nil
                                manualEntry = false
                                picked = nil
                                hits = []
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onDone() }
                }
            }
        }
        .tint(RexColor.primary)
    }

    private var categoryPicker: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(creatableCategories, id: \.self) { cat in
                Button {
                    withAnimation { category = cat }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: cat.symbol).font(.system(size: 22)).foregroundStyle(RexColor.primary)
                        Text(cat.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(RexColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func form(for category: RexCategory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let searchable: Set<RexCategory> = [.place, .event, .book, .movie, .tv, .podcast]
            let searchFirst = searchable.contains(category) && picked == nil && !manualEntry

            field(searchFirst ? "Search" : "Title", text: $title,
                  placeholder: searchFirst
                      ? "Search \(category.label.lowercased())s…"
                      : "e.g. \(placeholderTitle(for: category))")
                .onChange(of: title) { _, _ in scheduleSearch(for: category) }

            suggestions(for: category)

            if searchFirst {
                // Escape hatch for anything the catalogues don't have.
                Button {
                    manualEntry = true
                } label: {
                    HStack(spacing: RexSpacing.sm) {
                        Image(systemName: "square.and.pencil").font(.system(size: 12))
                        Text("Can't find it? Enter the details manually")
                            .font(RexFont.text(13, weight: .medium))
                    }
                    .foregroundStyle(RexColor.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RexSpacing.md)
                    .background(RexColor.badgeBackground)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if !searchFirst {
            field(subtitleLabel(for: category), text: $subtitle, placeholder: "Optional")

            if category == .place || category == .event {
                field("Address", text: $address, placeholder: "Optional")
            }

            if category == .trip {
                TripStopsBuilderView(stops: $tripStops)
            }

            if category == .recipe {
                RecipeEditorView(recipeText: $recipeText)
            }

            if let options = rexSubcategories[category], !options.isEmpty {
                Text(category == .place ? "Type of place" : "Type")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                FlowChips(options: options, selected: $subcategories)
            }

            // Somewhere to put a link to the thing itself — most useful on
            // Other (products, services) but harmless everywhere.
            field("Link (optional)", text: $productLink, placeholder: "https://…")
                .textInputAutocapitalization(.never)

            modePicker(for: category)

            if mode == .rated {
                Text("Your rating").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                CrownRatingInput(value: $rating)

                Text("Note").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                TextField("What did you love about it?", text: $note, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(12)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))

                Text("Photos").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                PhotoPickerView(photoURLs: $photoURLs)

                Toggle(isOn: $anonymous) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Post anonymously")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Text("Your name won't show. It still counts toward your Rex.")
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                }
                .tint(RexColor.primary)
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(RexColor.destructive)
            }

            Button(action: { Task { await post(category: category) } }) {
                if isSaving {
                    ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                } else {
                    Text(mode == .rated ? "Post" : addToWantLabel(for: category))
                        .fontWeight(.semibold).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 48)
            .background(title.trimmingCharacters(in: .whitespaces).isEmpty ? RexColor.primary.opacity(0.4) : RexColor.primary)
            .foregroundStyle(RexColor.primaryForeground)
            .clipShape(Capsule())
            .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.top, 6)
            }
        }
        .padding(16)
    }

    /// Live results from the external catalogues. Hidden once the user picks
    /// something, so the form stops nagging.
    @ViewBuilder
    private func suggestions(for category: RexCategory) -> some View {
        let searchable: Set<RexCategory> = [.place, .event, .book, .movie, .tv, .podcast]

        if searchable.contains(category) {
            if let picked {
                HStack(spacing: RexSpacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(RexColor.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(picked.title)
                            .font(RexFont.text(14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                            .lineLimit(1)
                        if let sub = picked.address ?? picked.subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button("Change") {
                        self.picked = nil
                        hits = []
                    }
                    .font(RexFont.text(12, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                }
                .padding(RexSpacing.md)
                .background(RexColor.badgeBackground)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            } else if isSearching || !hits.isEmpty {
                VStack(spacing: 0) {
                    if isSearching && hits.isEmpty {
                        HStack(spacing: RexSpacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("Searching…")
                                .font(RexFont.text(13))
                                .foregroundStyle(RexColor.mutedForeground)
                            Spacer()
                        }
                        .padding(RexSpacing.md)
                    }
                    ForEach(hits.prefix(6)) { hit in
                        Button {
                            apply(hit)
                        } label: {
                            HStack(spacing: RexSpacing.md) {
                                thumb(hit)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title)
                                        .font(RexFont.text(14, weight: .medium))
                                        .foregroundStyle(RexColor.foreground)
                                        .lineLimit(1)
                                    if let sub = hit.address ?? hit.subtitle, !sub.isEmpty {
                                        Text(sub)
                                            .font(RexFont.text(12))
                                            .foregroundStyle(RexColor.mutedForeground)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, RexSpacing.md)
                            .padding(.vertical, RexSpacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if hit.id != hits.prefix(6).last?.id {
                            Rectangle().fill(RexColor.divider).frame(height: 1)
                        }
                    }
                }
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                        .stroke(RexColor.border, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func thumb(_ hit: RexSearchHit) -> some View {
        Group {
            if let s = hit.imageURL, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else { RexColor.muted }
                }
            } else {
                RexColor.muted
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func apply(_ hit: RexSearchHit) {
        picked = hit
        title = hit.title
        // Google returns the place name in displayName, so its "subtitle" is
        // the address rather than an author/year.
        if hit.externalSource == "google_places" {
            subtitle = ""
            address = hit.address ?? ""
        } else {
            subtitle = hit.subtitle ?? ""
        }
        hits = []
    }

    /// Debounced so we're not firing a request per keystroke.
    private func scheduleSearch(for category: RexCategory) {
        searchTask?.cancel()
        guard picked == nil else { return }
        let term = title
        guard term.trimmingCharacters(in: .whitespaces).count >= 2 else {
            hits = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let results = await RexSearch.search(category: category, query: term)
            if Task.isCancelled { return }
            await MainActor.run {
                hits = results
                isSearching = false
            }
        }
    }

    @ViewBuilder
    private func modePicker(for category: RexCategory) -> some View {
        let wantLabel: String = {
            switch category {
            case .place: return "Want to visit"
            case .movie, .tv: return "Want to watch"
            default: return "Want to try"
            }
        }()
        HStack(spacing: 8) {
            modeButton("I've done it", isSelected: mode == .rated) { mode = .rated }
            modeButton(wantLabel, isSelected: mode == .want) { mode = .want }
        }
    }

    private func modeButton(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? RexColor.primary : RexColor.card)
                .foregroundStyle(isSelected ? RexColor.primaryForeground : RexColor.foreground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(RexColor.border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
            TextField(placeholder, text: text)
                .padding(12)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
        }
    }

    private func subtitleLabel(for category: RexCategory) -> String {
        switch category {
        case .book: return "Author"
        case .movie, .tv: return "Year or director"
        case .podcast: return "Host or network"
        case .recipe: return "Cookbook, chef, or source"
        case .event: return "Venue, date, or type"
        default: return "Subtitle"
        }
    }

    private func addToWantLabel(for category: RexCategory) -> String {
        switch category {
        case .place: return "Add to want to visit"
        case .movie, .tv: return "Add to want to watch"
        default: return "Add to want to try"
        }
    }

    private func placeholderTitle(for category: RexCategory) -> String {
        switch category {
        case .place: return "Dishoom"
        case .book: return "The Hobbit"
        case .movie: return "Inception"
        case .tv: return "Breaking Bad"
        case .podcast: return "This American Life"
        case .recipe: return "Koshari"
        case .event: return "Glastonbury"
        default: return "Title"
        }
    }

    private func post(category: RexCategory) async {
        isSaving = true
        errorMessage = nil
        do {
            let itemId = try await RexAPI.shared.createItem(
                type: category.rawValue,
                title: title.trimmingCharacters(in: .whitespaces),
                subtitle: subtitle.isEmpty ? nil : subtitle,
                address: (category == .place || category == .event) && !address.isEmpty ? address : nil,
                hit: picked,
                genre: subcategories.isEmpty ? nil : subcategories.sorted().joined(separator: ", "),
                linkURL: productLink.trimmingCharacters(in: .whitespaces).isEmpty ? nil : productLink.trimmingCharacters(in: .whitespaces),
                recipeText: category == .recipe && !recipeText.isEmpty ? recipeText : nil
            )
            // Trip stops become their own Rex, linked to the trip.
            if category == .trip, !tripStops.isEmpty {
                let tripRecId = try await RexAPI.shared.createRecommendation(
                    itemId: itemId,
                    rating: rating,
                    note: note.isEmpty ? nil : note,
                    photoURLs: photoURLs,
                    returningId: true
                )
                for stop in tripStops {
                    let stopItemId = try await RexAPI.shared.createItem(
                        type: stop.type.rawValue,
                        title: stop.title,
                        subtitle: stop.subtitle,
                        address: stop.address,
                        genre: stop.genre,
                        externalId: stop.externalId,
                        externalSource: stop.externalSource,
                        imageURL: stop.imageURL,
                        lat: stop.lat,
                        lng: stop.lng
                    )
                    _ = try await RexAPI.shared.createRecommendation(
                        itemId: stopItemId,
                        rating: stop.rating,
                        note: stop.note.isEmpty ? nil : stop.note,
                        tripId: tripRecId,
                        tripSection: stop.section
                    )
                }
                withAnimation { didPost = true }
                isSaving = false
                return
            }

            switch mode {
            case .rated:
                try await RexAPI.shared.createRecommendation(
                    itemId: itemId,
                    rating: rating,
                    note: note.isEmpty ? nil : note,
                    photoURLs: photoURLs,
                    anonymous: anonymous
                )
                didWant = false
            case .want:
                try await RexAPI.shared.createWant(itemId: itemId)
                didWant = true
            }
            withAnimation { didPost = true }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private var successState: some View {
        VStack(spacing: 16) {
            Image(systemName: didWant ? "bookmark.fill" : "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(RexColor.primary)
            Text(didWant ? "Saved" : "Posted")
                .font(RexFont.display(26, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text(didWant ? "\"\(title)\" is on your want-to list." : "\"\(title)\" is in your feed.")
                .font(.system(size: 15))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
            Button("Back to feed") { onDone() }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RexColor.primary)
                .foregroundStyle(RexColor.primaryForeground)
                .clipShape(Capsule())
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
