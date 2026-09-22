import SwiftUI
import PDFKit
import PhotosUI

// MARK: - Shared attachment model

struct AttachmentPreviewItem: Identifiable {
    let id: String  // file name
}

// MARK: - Attachment thumbnail (reused across sheets)

struct AttachmentThumbnailView: View {
    let fileName: String
    let visaID: UUID
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let url = VisaAttachmentStore.fileURL(fileName: fileName, visaID: visaID)
        let isPDF = fileName.lowercased().hasSuffix(".pdf")

        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if isPDF {
                        VStack(spacing: 4) {
                            Image(systemName: "doc.richtext.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.red)
                            Text("PDF")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 80, height: 80)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    } else if let data = try? Data(contentsOf: url),
                              let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 28))
                            .frame(width: 80, height: 80)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .background(Color.black.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview sheet

struct VisaAttachmentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let fileName: String
    let visaID: UUID

    private var fileURL: URL {
        VisaAttachmentStore.fileURL(fileName: fileName, visaID: visaID)
    }

    var body: some View {
        NavigationStack {
            previewContent
                .navigationTitle(displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: fileURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var previewContent: some View {
        if fileName.lowercased().hasSuffix(".pdf") {
            PDFKitView(url: fileURL)
        } else if let data = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: data) {
            ZoomableImageView(image: image)
        } else {
            ContentUnavailableView("Cannot Preview", systemImage: "doc.questionmark")
        }
    }

    private var displayTitle: String {
        let ext = (fileName as NSString).pathExtension.uppercased()
        return ext.isEmpty
            ? String(localized: "Attachment")
            : String(localized: "\(ext) Document")
    }
}

// MARK: - PDFKit view

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - Zoomable image view

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

        context.coordinator.imageView = imageView
        context.coordinator.image = image
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.fitImage(in: uiView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var image: UIImage?
        private var didFitOnce = false

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        func fitImage(in scrollView: UIScrollView) {
            guard !didFitOnce, let imageView, let image else { return }
            let size = scrollView.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            didFitOnce = true

            imageView.frame = CGRect(origin: .zero, size: image.size)
            scrollView.contentSize = image.size

            let scale = min(size.width / image.size.width, size.height / image.size.height)
            scrollView.minimumZoomScale = scale
            scrollView.zoomScale = scale
            centerImage(in: scrollView)
        }

        func centerImage(in scrollView: UIScrollView) {
            guard let imageView else { return }
            let sv = scrollView.bounds.size
            let iv = imageView.frame.size
            scrollView.contentInset = UIEdgeInsets(
                top:    max(0, (sv.height - iv.height) / 2),
                left:   max(0, (sv.width  - iv.width)  / 2),
                bottom: max(0, (sv.height - iv.height) / 2),
                right:  max(0, (sv.width  - iv.width)  / 2)
            )
        }
    }
}

// MARK: - Camera image picker

struct CameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
