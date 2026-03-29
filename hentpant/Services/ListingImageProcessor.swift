//
//  ListingImageProcessor.swift
//  hentpant
//

import CoreGraphics
import Foundation
import UIKit

struct ProcessedListingImage: Equatable, Sendable {
    let data: Data
    let fileExtension: String
    let mimeType: String
}

struct ListingImageProcessor {
    private let maxDimension: CGFloat
    private let compressionQuality: CGFloat

    init(maxDimension: CGFloat = 2_000, compressionQuality: CGFloat = 0.82) {
        self.maxDimension = maxDimension
        self.compressionQuality = compressionQuality
    }

    func process(data: Data) throws -> ProcessedListingImage {
        guard let image = UIImage(data: data) else {
            throw ListingImageProcessingError.invalidImageData
        }

        let normalized = resizedImageIfNeeded(from: image)
        guard let jpegData = renderedJPEGData(from: normalized) else {
            throw ListingImageProcessingError.jpegEncodingFailed
        }

        return ProcessedListingImage(
            data: jpegData,
            fileExtension: "jpg",
            mimeType: "image/jpeg"
        )
    }

    private func resizedImageIfNeeded(from image: UIImage) -> UIImage {
        let sourceSize = image.size
        let longestSide = max(sourceSize.width, sourceSize.height)

        guard longestSide > maxDimension, longestSide > 0 else {
            return image
        }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func renderedJPEGData(from image: UIImage) -> Data? {
        if let jpegData = image.jpegData(compressionQuality: compressionQuality) {
            return jpegData
        }

        let size = image.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let flattened = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return flattened.jpegData(compressionQuality: compressionQuality)
    }
}

enum ListingImageProcessingError: LocalizedError {
    case loadFailed
    case invalidImageData
    case jpegEncodingFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return String(localized: "The selected photo could not be loaded.")
        case .invalidImageData:
            return String(localized: "The selected photo format is not supported.")
        case .jpegEncodingFailed:
            return String(localized: "The selected photo could not be prepared for upload.")
        }
    }
}
