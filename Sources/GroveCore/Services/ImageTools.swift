import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image ready to store: at most `ImageTools.maxSide` pixels on its long side.
public struct PreparedImage: Equatable, Sendable {
    public var data: Data
    public var mime: String
    public var width: Int
    public var height: Int
}

public enum ImageTools {
    public static let maxSide = 1600

    /// Checks that `raw` is an image and shrinks it when it is large.
    /// A PNG or JPEG that already fits is kept byte for byte. Anything else is re-encoded
    /// (PNG when it has transparency, JPEG otherwise). Returns nil when `raw` is not an image.
    public static func prepare(_ raw: Data, maxSide: Int = ImageTools.maxSide) -> PreparedImage? {
        guard !raw.isEmpty,
              let source = CGImageSourceCreateWithData(raw as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }

        let type = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
        let long = max(width, height)
        if long <= maxSide, type == .png || type == .jpeg {
            return PreparedImage(data: raw, mime: type == .png ? "image/png" : "image/jpeg", width: width, height: height)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour the camera's rotation
            kCGImageSourceThumbnailMaxPixelSize: min(long, maxSide),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool ?? false
        let target: UTType = hasAlpha ? .png : .jpeg

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, target.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return PreparedImage(data: out as Data, mime: hasAlpha ? "image/png" : "image/jpeg", width: image.width, height: image.height)
    }
}
