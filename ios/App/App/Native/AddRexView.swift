import SwiftUI

/// v1 scope: category picker → manual entry form → post.
/// Skips live external search (Google/TMDB/etc — those are our own server functions over a
/// different RPC protocol, not plain Supabase REST) and skips Trips (needs the stops builder).
/// "Enter details manually" is exactly the fallback path the web app already offers, so this
/// is a real, working subset of Add a Rex rather than a stub.
struct AddRexView: View {
    var onDone: () -> Void

    private let creatableCategories: [RexCategory] = [.place, .book, .movie, .tv, .podcast, .recipe, .event, .other]

    private enum Mode { case rated, want }

    @State private var category: RexCategory?
    @State private var mode: Mode = .rated
    @State private var title = ""
    @State private var subtitle = ""
    @State private var address = ""
    @State private var rating: Double = 10
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didPost = false
    @State private var didWant = false

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
                        Button("Back") { withAnimation { category = nil } }
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
            field("Title", text: $title, placeholder: "e.g. \(placeholderTitle(for: category))")

            field(subtitleLabel(for: category), text: $subtitle, placeholder: "Optional")

            if category == .place || category == .event {
                field("Address", text: $address, placeholder: "Optional")
            }

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
        .padding(16)
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
                address: (category == .place || category == .event) && !address.isEmpty ? address : nil
            )
            switch mode {
            case .rated:
                try await RexAPI.shared.createRecommendation(itemId: itemId, rating: rating, note: note.isEmpty ? nil : note)
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
            Text(didWant ? "📌" : "🦖").font(.system(size: 56))
            Text(didWant ? "Saved!" : "Nice one!").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(RexColor.foreground)
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
