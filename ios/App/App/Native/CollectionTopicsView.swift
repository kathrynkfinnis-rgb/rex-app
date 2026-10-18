import SwiftUI

/// Oct 18 — "the topics work well but need to have the option to categorise
/// in the main collections screen as well."
///
/// Topics have existed since 12 October and do exactly what was asked for:
/// one shelf per topic on the Collections screen, so you can have "Film
/// collections" and "Restaurant collections" with London and Lisbon inside.
/// What was wrong was the way in. You set a topic from *inside* a collection,
/// three taps deep in an overflow menu that also holds Rename, Add a Rex,
/// Import, Sections & order and Who can see it — so organising five
/// collections meant visiting five collections, and nobody looking at the
/// Collections screen would ever find it.
///
/// This is the same setting, gathered into the one place the job is actually
/// thought about: every collection you own, its topic beside it, changeable
/// without leaving. The per-collection menu stays where it is — it is the
/// right place when you are already in there and only want to move that one.
struct CollectionTopicsView: View {
    let lists: [RexList]
    /// Called after every change, so the shelves behind this re-draw.
    var onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var topics: [String: String?] = [:]
    @State private var namingFor: RexList?
    @State private var newTopicDraft = ""
    @State private var busyId: String?
    @State private var errorMessage: String?

    /// Every topic in use, so moving a collection into one is a choice rather
    /// than a spelling test — "London" and "london" would be two shelves and
    /// nobody meant that.
    private var existingTopics: [String] {
        let live = lists.map { topics[$0.id] ?? $0.topic }
        return Array(Set(live.compactMap {
            $0?.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty })).sorted { $0.lowercased() < $1.lowercased() }
    }

    private func topic(for list: RexList) -> String? {
        (topics[list.id] ?? list.topic)?.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Group {
                if lists.isEmpty {
                    Text("No collections yet.")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            Text("Group your collections into shelves. Each topic becomes its own row on the Collections screen.")
                                .font(RexFont.text(13))
                                .foregroundStyle(RexColor.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, RexSpacing.page)
                                .padding(.bottom, RexSpacing.md)

                            ForEach(lists) { list in
                                row(list)
                                Divider().overlay(RexColor.divider)
                                    .padding(.leading, RexSpacing.page)
                            }
                        }
                        .padding(.top, RexSpacing.md)
                    }
                }
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Organise collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
        .alert("New topic", isPresented: Binding(
            get: { namingFor != nil },
            set: { if !$0 { namingFor = nil } }
        )) {
            TextField("Topic", text: $newTopicDraft)
            Button("Cancel", role: .cancel) { namingFor = nil }
            Button("Save") {
                let name = newTopicDraft.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, let list = namingFor else { return }
                namingFor = nil
                Task { await set(name, on: list) }
            }
        } message: {
            Text("A shelf of its own on the Collections screen \u{2014} \u{201C}Film collections\u{201D}, say.")
        }
        .alert("Couldn't move that", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func row(_ list: RexList) -> some View {
        let current = topic(for: list)
        HStack(spacing: RexSpacing.md) {
            Text(list.emoji ?? "\u{1F4C1}")
                .font(.system(size: 20))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(RexFont.text(15, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(1)
                Text(current?.isEmpty == false ? current! : "No topic")
                    .font(RexFont.text(12.5))
                    .foregroundStyle(current?.isEmpty == false ? RexColor.primary : RexColor.mutedForeground)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if busyId == list.id {
                ProgressView()
            } else {
                Menu {
                    ForEach(existingTopics, id: \.self) { name in
                        Button {
                            Task { await set(name, on: list) }
                        } label: {
                            Label(name, systemImage: current == name ? "checkmark" : "folder")
                        }
                    }
                    if current?.isEmpty == false {
                        Button {
                            Task { await set(nil, on: list) }
                        } label: {
                            Label("No topic", systemImage: "folder.badge.minus")
                        }
                    }
                    Button {
                        newTopicDraft = ""
                        namingFor = list
                    } label: {
                        Label("New topic\u{2026}", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(RexColor.primary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, RexSpacing.page)
        .padding(.vertical, RexSpacing.md)
    }

    /// Writes the change and keeps it on screen. The local override means the
    /// row updates before the Collections screen behind has refetched, so the
    /// menu never shows a tick against what it used to say.
    private func set(_ name: String?, on list: RexList) async {
        busyId = list.id
        defer { busyId = nil }
        do {
            try await RexAPI.shared.setCollectionTopic(id: list.id, topic: name)
            topics[list.id] = name
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
