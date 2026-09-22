import SwiftUI
import VisionKit

struct MRZCamera: UIViewControllerRepresentable {
    var completed: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completed: (Data?) -> Void
        init(completed: @escaping (Data?) -> Void) { self.completed = completed }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { completed(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { completed(Data()) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { completed(nil); return }
            // Image is held in memory for local OCR only, never saved or uploaded.
            completed(scan.imageOfPage(at: 0).jpegData(compressionQuality: 0.95) ?? Data())
        }
    }
}
