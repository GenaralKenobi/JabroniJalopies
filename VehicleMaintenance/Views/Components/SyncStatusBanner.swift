import SwiftUI

/// Shows when the phone is offline or photos are still waiting to upload.
struct SyncStatusBanner: View {
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(PhotoUploadQueue.self) private var photoQueue

    var body: some View {
        if !connectivity.isOnline || photoQueue.pendingCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: connectivity.isOnline ? "arrow.up.circle" : "wifi.slash")
                    Text(message)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                if connectivity.isOnline, let error = photoQueue.lastError {
                    Text(error)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") { photoQueue.process() }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(bannerColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var bannerColor: Color {
        if !connectivity.isOnline { return .gray }
        return photoQueue.lastError == nil ? .blue : .orange
    }

    private var message: String {
        let photos = photoQueue.pendingCount
        let photoText = photos == 1 ? "1 photo waiting to upload" : "\(photos) photos waiting to upload"
        if !connectivity.isOnline {
            return photos > 0 ? "Offline — changes and \(photoText.replacingOccurrences(of: " waiting to upload", with: "")) will sync later" : "Offline — changes will sync when you're back online"
        }
        return photoText
    }
}

extension View {
    func syncStatusBanner() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { SyncStatusBanner() }
    }
}
