import SwiftUI
import UIKit

/// Oct 13 — "when adding a recipe and import from photo, can you go direct to
/// camera rather than having to take photo first."
///
/// The camera, in the app. Until now "Import from photo" opened the library,
/// so photographing a cookbook page meant leaving Rex, taking the picture,
/// coming back and finding it again — four steps for what is one intention.
///
/// UIImagePickerController rather than anything newer because this needs the
/// system camera UI and a single still image back, which is exactly what it
/// does and all it does. The modern replacements are for picking from the
/// library, which is the other button.
///
/// `isAvailable` matters: the Simulator has no camera, and so does a device
/// where the camera is restricted by Screen Time. Asking for one that isn't
/// there presents an empty black sheet, so the caller checks first and falls
/// back to the library.
struct RexCameraPicker: UIViewControllerRepresentable {
    /// Nov 7 — was hardcoded true, for the one caller that wanted it. A
    /// recipe is a flat page and the crop box is how you cut the facing page
    /// and your own thumb out before anything is read. An ordinary photo of
    /// your dinner is not that: forcing a crop box in front of every shot
    /// makes taking one a two-step job, and PhotoPickerView already puts a
    /// crop button on each photo afterwards, where it is optional.
    /// Declared before onCapture so the trailing closure still reads as one:
    /// RexCameraPicker(allowsEditing: true) { image in … }
    var allowsEditing = false
    var onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = allowsEditing
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // The edited image when the crop box was used, the original when
            // it wasn't — in that order, because a crop is the user telling us
            // which part of the page they meant.
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                onCapture(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
