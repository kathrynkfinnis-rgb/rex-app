import SwiftUI
import UIKit

/// Oct 14 — "when I write something, I won't be able to add a hyperlink", and
/// then plainly: hyperlinking selected words in a comment.
///
/// Kathryn's example was typing "Ultra Violette" in a reply and wanting those
/// two words to be the link, rather than pasting a URL beside them. iOS has
/// the right gesture for this already — select, then pick from the menu that
/// appears — and SwiftUI's TextField does not expose a selection or let you
/// add to that menu. So this is a UITextView with one extra item on it.
///
/// What it writes is markdown: `[Ultra Violette](https://…)`. Plain text, so
/// it survives a database column, an edit on the web and a copy into a
/// message, and if anything ever fails to parse it you get readable words and
/// a visible address rather than nothing. `linkified()` turns it back into a
/// tappable run wherever text is shown.
struct RexLinkableTextEditor: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Raised when somebody picks "Link" with words selected. The caller asks
    /// for the address and calls back through `applyLink`.
    var onRequestLink: (NSRange, String) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.isScrollEnabled = true
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        // The placeholder is a label behind the text rather than UITextView's
        // own (it has none), shown and hidden as the text changes.
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = view.font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 9),
            placeholderLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -9),
        ])
        context.coordinator.placeholderLabel = placeholderLabel
        placeholderLabel.isHidden = !text.isEmpty
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: RexLinkableTextEditor
        var placeholderLabel: UILabel?

        init(_ parent: RexLinkableTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            placeholderLabel?.isHidden = !textView.text.isEmpty
        }

        /// The selection menu, plus one item. Only offered when something is
        /// actually selected: "Link" with nothing to link is a dead control.
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else { return UIMenu(children: suggestedActions) }
            let selected = (textView.text as NSString).substring(with: range)
            let link = UIAction(title: "Link", image: UIImage(systemName: "link")) { [weak self] _ in
                self?.parent.onRequestLink(range, selected)
            }
            return UIMenu(children: suggestedActions + [link])
        }
    }

    /// Wraps `range` in markdown pointing at `url`. Lives here rather than at
    /// the call site so the one place that writes this format is the same
    /// place that documents it.
    static func applyLink(to text: String, range: NSRange, url: String) -> String {
        let ns = text as NSString
        guard range.location != NSNotFound, range.location + range.length <= ns.length else { return text }
        let words = ns.substring(with: range)
        let address = url.hasPrefix("http") ? url : "https://\(url)"
        return ns.replacingCharacters(in: range, with: "[\(words)](\(address))")
    }
}
