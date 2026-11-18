import SwiftUI

/// Shows a defect photo: the copy saved on this phone (downloading it once if needed),
/// the local copy if it's still waiting to upload, or a placeholder.
struct DefectPhotoView: View {
    let photoId: String
    let photo: DefectPhoto
    var size: CGFloat = 110

    @Environment(PhotoUploadQueue.self) private var queue
    @Environment(ConnectivityMonitor.self) private var connectivity
    @State private var image: UIImage?
    @State private var loadFailed = false
    @State private var showingFull = false

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { if hasImage { showingFull = true } }
            .task(id: "\(photo.path ?? "")-\(connectivity.isOnline)") {
                guard let path = photo.path, image == nil else { return }
                if let data = await PhotoCache.shared.load(path), let loaded = UIImage(data: data) {
                    image = loaded
                    loadFailed = false
                } else {
                    loadFailed = true
                }
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

    private var hasImage: Bool { image != nil || localImage != nil }

    private var localImage: UIImage? {
        queue.localImageData(photoId: photoId).flatMap(UIImage.init(data:))
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
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
        } else if loadFailed {
            placeholder(connectivity.isOnline ? "Can't load photo" : "Not saved on this phone yet. Needs signal.",
                        symbol: connectivity.isOnline ? "exclamationmark.triangle" : "wifi.slash")
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
