import SwiftUI
import UIKit

/// Sept 21 — "still can't hide the keyboard when I want to — need to be able
/// to do this on every place you use a keyboard."
///
/// There was already a `Done` button above the keyboard and a swipe-down
/// dismiss on scroll views, added a screen at a time. Neither is the thing
/// people actually do, which is tap the empty space next to the field. And
/// being per-screen, every new form had to remember to opt in, and the ones
/// that didn't — a rename alert, a search box, a sheet that doesn't scroll —
/// had no way out of the keyboard at all.
///
/// So this is installed once, on the window, and covers every text field in
/// the app including the ones that don't exist yet. `cancelsTouchesInView`
/// stays false, so the tap still reaches whatever was underneath: tapping a
/// button while the keyboard is up both dismisses the keyboard and presses
/// the button, which is what you'd expect it to do.
@MainActor
final class RexKeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = RexKeyboardDismisser()

    private weak var installedOn: UIWindow?

    func install() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first
        else { return }
        guard installedOn !== window else { return }

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        // The tap is an extra listener, not an interceptor.
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        installedOn = window
    }

    @objc private func dismissKeyboard() {
        installedOn?.endEditing(true)
    }

    /// Never win against anything else. A tap that also hits a button, a card,
    /// a map pin or a scroll view should do both things, not steal the touch.
    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    /// Don't fire when there's no keyboard to hide, and don't fire for a tap
    /// that landed inside the text field itself — moving the cursor within
    /// what you're typing shouldn't close the keyboard under you.
    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        MainActor.assumeIsolated {
            guard let view = touch.view else { return true }
            if view is UITextField || view is UITextView { return false }
            // A SwiftUI TextField is a UITextField inside a wrapper or two —
            // walk up far enough to catch the padding around it.
            var ancestor = view.superview
            var depth = 0
            while let current = ancestor, depth < 4 {
                if current is UITextField || current is UITextView { return false }
                ancestor = current.superview
                depth += 1
            }
            return true
        }
    }
}

extension View {
    /// Installs the window-wide tap-to-dismiss once, from the root view, by
    /// which point there is a window to attach it to.
    func rexInstallsKeyboardDismissal() -> some View {
        task { RexKeyboardDismisser.shared.install() }
    }
}
