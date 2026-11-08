import UIKit

enum ImageProcessing {
    /// Shrinks a photo so vehicle images don't bloat the database.
    static func downscaledJPEG(_ data: Data, maxDimension: CGFloat = 1200, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longestSide)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Photo of a defect: sized to stay readable but upload over a weak signal (~300–500 KB).
    static func defectPhotoJPEG(_ image: UIImage) -> Data? {
        jpeg(image, maxDimension: 1600, quality: 0.7)
    }

    static func jpeg(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return nil }
        let scale = min(1, maxDimension / longestSide)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // Re-rendering also drops EXIF metadata such as GPS location.
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
