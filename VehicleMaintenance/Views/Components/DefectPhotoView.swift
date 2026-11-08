import FirebaseStorage
import SwiftUI

/// Shows a defect photo: the uploaded copy, the local copy if it's still
/// waiting on this phone, or a placeholder if it's waiting on someone else's.
struct DefectPhotoView: View {
    let photoId: String
    let photo: DefectPhoto
    var size: CGFloat = 110

    @Environment(PhotoUploadQueue.self) private var queue
    @State private var url: URL?
    @State private var showingFull = false

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { if hasImage { showingFull = true } }
            .task(id: photo.path) {
                guard let path = photo.path, url == nil else { return }
                url = try? await Storage.storage().reference(withPath: path).downloadURL()
            }
            .sheet(isPresented: $showingFull) {
                NavigationStack {
                    content
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFull = false } }
                        }
                }
            }
    }

    private var hasImage: Bool { url != nil || localImage != nil }

    private var localImage: UIImage? {
        queue.localImageData(photoId: photoId).flatMap(UIImage.init(data:))
    }

    @ViewBuilder
    private var content: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: placeholder("Can't load photo", symbol: "exclamationmark.triangle")
                default: ZStack { Rectangle().fill(.quaternary); ProgressView() }
                }
            }
        } else if let localImage {
            Image(uiImage: localImage)
                .resizable()
                .scaledToFill()
                .overlay(alignment: .bottomLeading) {
                    Label("Uploading", systemImage: "arrow.up.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(4)
                }
        } else if photo.status == .pending {
            let stale = Date.now.timeIntervalSince(photo.addedAt) > 24 * 3600
            placeholder(stale ? "Photo never arrived — ask \(photo.addedByName)" : "Photo pending from \(photo.addedByName)'s phone",
                        symbol: stale ? "exclamationmark.triangle" : "camera.badge.clock")
        } else {
            ZStack { Rectangle().fill(.quaternary); ProgressView() }
        }
    }

    private func placeholder(_ text: String, symbol: String) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(text)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }
            .foregroundStyle(Color.secondary)
        }
    }
}
