import SwiftUI

/// Make an empty collection, then fill it from any Rex.
struct NewCollectionView: View {
    var onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = ""
    @State private var type: RexCategory = .place
    @State private var visibility = "draft"
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let suggestedEmoji = ["\u{1F4D2}", "\u{1F37D}", "\u{2708}", "\u{1F4DA}", "\u{1F3AC}", "\u{1F3A7}", "\u{1F3E0}", "\u{1F378}"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    field("Name") {
                        TextField("e.g. Best pubs in London", text: $name)
                            .font(RexFont.text(16))
                            .padding(.horizontal, RexSpacing.lg)
                            .frame(height: 52)
                            .background(RexColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                    .stroke(RexColor.border, lineWidth: 1)
                            )
                    }

                    field("Icon") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: RexSpacing.sm) {
                                ForEach(suggestedEmoji, id: \.self) { e in
                                    Button { emoji = (emoji == e ? "" : e) } label: {
                                        Text(e)
                                            .font(.system(size: 22))
                                            .frame(width: 48, height: 48)
                                            .background(emoji == e ? RexColor.badgeBackground : RexColor.card)
                                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                                    .stroke(emoji == e ? RexColor.primary : RexColor.border, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    field("Mostly about") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: RexSpacing.sm) {
                                ForEach(rexAllCategories, id: \.self) { c in
                                    Button { type = c } label: {
                                        Text(c.label)
                                            .font(RexFont.text(13, weight: type == c ? .semibold : .regular))
                                            .foregroundStyle(type == c ? RexColor.primaryForeground : RexColor.mutedForeground)
                                            .padding(.horizontal, RexSpacing.md)
                                            .padding(.vertical, 7)
                                            .background(type == c ? RexColor.primary : RexColor.card)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(type == c ? RexColor.primary : RexColor.border, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    field("Who can see it") {
                        VStack(spacing: 0) {
                            visibilityRow("draft", "Only me", "Keep it private while you build it up.", "lock")
                            Divider().overlay(RexColor.border)
                            visibilityRow("friends", "Friends", "Anyone you're friends with on REX.", "person.2")
                            Divider().overlay(RexColor.border)
                            visibilityRow("public", "Anyone on REX", "Friends can share it on.", "globe")
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

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(RexColor.primaryForeground)
                        } else {
                            Text("Create collection")
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("New collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text(label)
                .font(RexFont.text(14, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            content()
        }
    }

    private func visibilityRow(_ value: String, _ title: String, _ blurb: String, _ symbol: String) -> some View {
        Button {
            visibility = value
        } label: {
            HStack(spacing: RexSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(RexColor.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(RexFont.text(15, weight: .medium))
                        .foregroundStyle(RexColor.foreground)
                    Text(blurb)
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                }
                Spacer()
                Image(systemName: visibility == value ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(visibility == value ? RexColor.primary : RexColor.border)
            }
            .padding(RexSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            let id = try await RexAPI.shared.createCollection(
                name: name.trimmingCharacters(in: .whitespaces),
                emoji: emoji.isEmpty ? nil : emoji,
                itemType: type.rawValue
            )
            if visibility != "draft" {
                try? await RexAPI.shared.setCollectionVisibility(id: id, visibility: visibility)
            }
            onCreated(id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
