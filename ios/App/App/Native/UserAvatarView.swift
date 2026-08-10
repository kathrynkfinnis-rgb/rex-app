import SwiftUI

/// Profile picture with an initial as the fallback. Mirrors the web UserAvatar.
/// Avatar URLs are long-lived signed URLs from the `avatars` bucket.
struct UserAvatarView: View {
    let url: String?
    let name: String
    var size: CGFloat = 24

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url), !url.isEmpty {
                AsyncImage(url: parsed) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(RexColor.border, lineWidth: 0.5))
    }

    private var fallback: some View {
        ZStack {
            RexColor.badgeBackground
            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(RexColor.badgeForeground)
        }
    }
}
