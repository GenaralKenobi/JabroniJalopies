import SwiftUI

/// Shows when the phone is offline or photos are still waiting to upload.
struct SyncStatusBanner: View {
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(PhotoUploadQueue.self) private var photoQueue

    var body: some View {
        if !connectivity.isOnline || photoQueue.pendingCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: connectivity.isOnline ? "arrow.up.circle" : "wifi.slash")
                Text(message)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(connectivity.isOnline ? Color.blue : Color.gray, in: Capsule())
            .padding(.horizontal)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
        }
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
