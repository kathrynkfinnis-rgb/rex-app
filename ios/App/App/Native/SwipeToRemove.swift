import SwiftUI

/// A rect, in SwipeToRemove's own coordinate space, that its delete-swipe
/// gesture should not claim — reported by any subview that has its own
/// horizontal swipe (currently just PhotoCarouselView's paging).
/// `nil` means "nothing has reported a zone"; a `.zero` rect is a real,
/// reported empty zone, so this can't just default to CGRect.zero.
private struct SwipeExclusionZoneKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        // Last write wins — a card has at most one such subview (the photo
        // carousel), so there's never really a second writer in practice.
        value = nextValue() ?? value
    }
}

extension View {
    /// Mark this view as its own swipe target: SwipeToRemove.swiftCardSpace
    /// must be the enclosing SwipeToRemove for this to have any effect —
    /// elsewhere it's a harmless, unread preference write.
    func swipeToRemoveExclusionZone() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SwipeExclusionZoneKey.self,
                    value: geo.frame(in: .named(SwipeToRemove<AnyView>.coordinateSpaceName))
                )
            }
        )
    }
}

/// Right-to-left swipe to reveal a destructive action.
///
/// `List`'s own `.swipeActions` isn't available to us — the feed, collections
/// and profile are all ScrollViews so that cards can size themselves — so this
/// rebuilds the gesture.
///
/// The content must NOT be a Button or NavigationLink: their own gesture beats
/// any drag attached alongside, so the swipe just registers as a tap. Pass the
/// plain card and hand the tap back through `onTap` instead.
struct SwipeToRemove<Content: View>: View {
    let label: String
    let systemImage: String
    /// Ask first. Worth it for deleting a Rex; needless for un-saving one.
    var confirmMessage: String?
    /// What tapping the row does — usually pushing a detail screen.
    var onTap: () -> Void = {}
    let action: () async -> Void
    @ViewBuilder var content: () -> Content

    private let actionWidth: CGFloat = 92
    /// Past this, letting go performs the action rather than parking it open.
    private let commitWidth: CGFloat = 200

    @State private var offset: CGFloat = 0
    /// Where the row sat when this drag started. Read live, it compounds with
    /// the translation and the row runs away from the finger.
    @State private var dragStart: CGFloat?
    @State private var isConfirming = false
    @State private var isWorking = false

    /// Reported by a subview (PhotoCarouselView, via
    /// .swipeToRemoveExclusionZone()) that has its own horizontal swipe —
    /// a drag starting inside this rect belongs to that subview instead.
    @State private var exclusionZone: CGRect?
    /// Decided once, when a drag starts, from exclusionZone — a drag can't
    /// change which view owns it partway through.
    @State private var isDragExcluded = false

    static var coordinateSpaceName: String { "swipeToRemoveCard" }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                trigger()
            } label: {
                VStack(spacing: 4) {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
                        Text(label).font(RexFont.text(11, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(RexColor.destructive)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(offset < -8 ? 1 : 0)

            content()
                .background(RexColor.background)
                .contentShape(Rectangle())
                .offset(x: offset)
                .onTapGesture {
                    // A tap while the action is showing just puts it away.
                    if offset < 0 { close() } else { onTap() }
                }
                // .highPriorityGesture rather than plain .gesture: this view
                // lives inside a ScrollView, and ScrollView's own pan gesture
                // (backed by UIScrollView.panGestureRecognizer, a separate
                // UIKit recognizer from SwiftUI's gesture system) was winning
                // outright on any drag, including clearly-horizontal ones —
                // confirmed by testing: a horizontal swipe just scrolled the
                // list vertically instead of revealing the delete action.
                // highPriorityGesture is the documented way to make a child's
                // gesture take precedence over an ancestor's, which plain
                // .gesture does not do.
                //
                // That same priority-over-descendants behavior is exactly
                // what broke the photo carousel's own swipe (#120/#111
                // regression): once this card started fielding a photo
                // carousel, ITS internal paging drag is a descendant of
                // this highPriorityGesture too, so it lost every time a
                // swipe started on the photo. coordinateSpaceName +
                // exclusionZone below carve that region back out — a drag
                // whose start point lands inside the reported carousel
                // frame is marked excluded up front and this gesture does
                // nothing for its whole lifetime, leaving the touch free
                // for the carousel's own TabView to handle.
                .coordinateSpace(name: Self.coordinateSpaceName)
                .onPreferenceChange(SwipeExclusionZoneKey.self) { exclusionZone = $0 }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 14, coordinateSpace: .named(Self.coordinateSpaceName))
                        .onChanged { value in
                            if dragStart == nil {
                                isDragExcluded = exclusionZone?.contains(value.startLocation) ?? false
                                dragStart = offset
                            }
                            guard !isDragExcluded else { return }
                            // Ignore anything that's really a scroll.
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let base = dragStart ?? offset
                            offset = min(0, max(base + value.translation.width, -commitWidth - 40))
                        }
                        .onEnded { value in
                            defer { dragStart = nil; isDragExcluded = false }
                            guard !isDragExcluded else { return }
                            guard abs(value.translation.width) > abs(value.translation.height) || offset < 0 else { return }
                            // No commit-on-full-swipe: a long flick is too easy
                            // to do by accident, and this deletes things.
                            if offset < -actionWidth / 2 {
                                withAnimation(.snappy) { offset = -actionWidth }
                            } else {
                                withAnimation(.snappy) { offset = 0 }
                            }
                        }
                )
        }
        .alert(confirmMessage ?? "", isPresented: $isConfirming) {
            Button("Cancel", role: .cancel) { close() }
            Button(label, role: .destructive) { perform() }
        }
    }

    private func trigger() {
        if confirmMessage != nil {
            isConfirming = true
        } else {
            perform()
        }
    }

    private func perform() {
        isWorking = true
        Task {
            await action()
            isWorking = false
            close()
        }
    }

    private func close() {
        withAnimation(.snappy) { offset = 0 }
    }
}
