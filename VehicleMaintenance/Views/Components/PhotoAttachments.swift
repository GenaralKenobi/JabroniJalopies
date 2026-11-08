import PhotosUI
import SwiftUI

/// Camera wrapper (PhotosPicker covers the library).
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Lets the user take or choose photos. Each photo gets an id and is stored as
/// a downsized JPEG in `photos`; `photoIds` keeps the order for one item.
struct PhotoAttachmentControls: View {
    @Binding var photoIds: [String]
    @Binding var photos: [String: Data]
    var maxCount = 4

    @State private var showingCamera = false
    @State private var libraryItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !photoIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photoIds, id: \.self) { id in
                            if let data = photos[id], let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            photoIds.removeAll { $0 == id }
                                            photos[id] = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .buttonStyle(.borderless)
                                        .padding(2)
                                        .accessibilityLabel("Remove photo")
                                    }
                            }
                        }
                    }
                }
            }

            if photoIds.count < maxCount {
                HStack(spacing: 16) {
                    if CameraPicker.isAvailable {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                    }
                    PhotosPicker(selection: $libraryItems, maxSelectionCount: maxCount - photoIds.count, matching: .images) {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in add(image) }
                .ignoresSafeArea()
        }
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        add(image)
                    }
                }
                libraryItems = []
            }
        }
    }

    private func add(_ image: UIImage) {
        guard photoIds.count < maxCount, let data = ImageProcessing.defectPhotoJPEG(image) else { return }
        let id = UUID().uuidString
        photos[id] = data
        photoIds.append(id)
    }
}
