import SwiftUI

struct RecommendationCardView: View {
    let rec: FeedRecommendation

    private var category: RexCategory { RexCategory(rawType: rec.items?.type) }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var relativeTime: String {
        guard let date = rec.createdDate else { return "" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var ratingText: String {
        rec.rating.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rec.rating)
            : String(format: "%.1f", rec.rating)
    }

    var body: some View {
        guard let item = rec.items else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    thumbnail(item: item)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            HStack(spacing: 3) {
                                Image(systemName: category.symbol).font(.system(size: 9))
                                Text(category.label.uppercased()).font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(RexColor.primary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RexColor.primary.opacity(0.12))
                            .clipShape(Capsule())

                            Spacer()

                            HStack(spacing: 2) {
                                Image(systemName: "crown.fill").font(.system(size: 11)).foregroundStyle(RexColor.primary)
                                Text(ratingText).fontWeight(.semibold)
                                Text("/10").foregroundStyle(RexColor.mutedForeground)
                            }
                            .font(.system(size: 14))
                        }

                        Text(item.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(RexColor.foreground)
                            .lineLimit(1)

                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(RexColor.mutedForeground)
                                .lineLimit(1)
                        }

                        if let note = rec.note, !note.isEmpty {
                            Text("\u{201C}\(note)\u{201D}")
                                .font(.system(size: 13))
                                .foregroundStyle(RexColor.foreground.opacity(0.9))
                                .lineLimit(2)
                                .padding(.top, 2)
                        }

                        if let tags = rec.tags, !tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(tags.prefix(4), id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(RexColor.primary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(RexColor.primary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .padding(12)

                Divider().overlay(RexColor.border)

                HStack(spacing: 8) {
                    authorRow
                    Spacer()
                    Text(relativeTime)
                        .font(.system(size: 10))
                        .foregroundStyle(RexColor.mutedForeground.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(RexColor.border, lineWidth: 1)
            )
        )
    }

    @ViewBuilder
    private func thumbnail(item: RexItem) -> some View {
        Group {
            if let urlString = item.image_url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RexColor.muted
                    }
                }
            } else {
                RexColor.muted.overlay(
                    Image(systemName: category.symbol)
                        .foregroundStyle(RexColor.mutedForeground)
                )
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var authorRow: some View {
        if let creator = rec.creators {
            HStack(spacing: 4) {
                Text(creator.emoji ?? "\u{1F3A4}")
                Text(creator.name).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(hex: creator.color.replacingOccurrences(of: "#", with: "")))
            .clipShape(Capsule())
        } else if let author = rec.profiles {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(RexColor.secondary)
                    Text(String((author.display_name ?? author.username).prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RexColor.secondaryForeground)
                }
                .frame(width: 22, height: 22)

                Text(author.display_name ?? author.username)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(1)
            }
        } else {
            Text("Someone").font(.system(size: 13, weight: .medium)).foregroundStyle(RexColor.foreground)
        }
    }
}
