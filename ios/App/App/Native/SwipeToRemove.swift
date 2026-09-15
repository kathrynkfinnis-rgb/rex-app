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
                // While Delete is showing, a tap anywhere on the card closes
                // it — including on a part with a tap of its own (a long
                // note expands, a location opens the map), which would
                // otherwise take the tap and leave Delete sitting open.
                .overlay {
                    if offset < 0 {
                        Color.clear
                            .contentShape(Rectangle())
                            .offset(x: offset)
                            .onTapGesture { close() }
                    }
                }
                // Sept 15 — the third and hopefully last shape of this.
                //
                // highPriorityGesture (Aug) claimed every drag that started on
                // the card, vertical ones included, so the feed couldn't be
                // scrolled from your own cards (Danny, 14 Sept).
                // simultaneousGesture (build 40) fixed that but let this drag
                // run alongside the photo carousel's own swipe — "I can't
                // scroll through the carousel of photos any more".
                //
                // A SwiftUI DragGesture can't say "only horizontal" before it
                // starts, which is the whole problem. A UIKit pan can: its
                // delegate is asked whether to begin once the finger has
                // moved, and says no for anything mostly vertical (so the
                // feed scrolls) or anything that starts inside a sideways
                // scroller (so the carousel pages). See HorizontalSwipeGesture.
                .gesture(
                    HorizontalSwipeGesture(
                        onChanged: { translation in
                            if dragStart == nil { dragStart = offset }
                            let base = dragStart ?? offset
                            offset = min(0, max(base + translation, -commitWidth - 40))
                        },
                        onEnded: { _ in
                            defer { dragStart = nil }
                            // No commit-on-full-swipe: a long flick is too
                            // easy to do by accident, and this deletes things.
                            if offset < -actionWidth / 2 {
                                withAnimation(.snappy) { offset = -actionWidth }
                            } else {
                                withAnimation(.snappy) { offset = 0 }
                            }
                        }
                    )
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


/// A left/right pan that only ever starts for a sideways swipe.
///
/// - Mostly-vertical movement: declines to begin, and the scroll view it
///   sits in (which waits for this to decide — see shouldBeRequiredToFailBy)
///   scrolls as normal.
/// - Starting inside something that itself scrolls sideways (the photo
///   carousel's pager): declines, so that scroller gets the swipe.
private struct HorizontalSwipeGesture: UIGestureRecognizerRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let x = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed: onChanged(x)
        case .ended, .cancelled, .failed: onEnded(x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            guard abs(velocity.x) > abs(velocity.y) * 1.2 else { return false }
            // Walk up from whatever the touch landed on: a horizontal
            // scroller on the way up means the swipe is its.
            var hit = view.hitTest(pan.location(in: view), with: nil)
            while let current = hit, current !== view {
                if let scroller = current as? UIScrollView,
                   scroller.contentSize.width > scroller.bounds.width + 1 {
                    return false
                }
                hit = current.superview
            }
            return true
        }

        /// The feed's vertical scroll view waits (for the length of one
        /// decision) until this has declined — otherwise it would start
        /// scrolling on the same sideways swipe that should reveal Delete.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scroller = otherGestureRecognizer.view as? UIScrollView,
                  otherGestureRecognizer === scroller.panGestureRecognizer else { return false }
            // Vertical scrollers only; a sideways one (the carousel) must
            // never wait on this.
            return scroller.contentSize.width <= scroller.bounds.width + 1
        }
    }
}
