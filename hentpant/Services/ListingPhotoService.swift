//
//  ListingPhotoService.swift
//  hentpant
//

import Foundation
import OSLog
import Supabase

struct ListingPhotoUploadPlan: Equatable, Sendable {
    let path: String
    let image: ProcessedListingImage
}

struct ListingPhotoService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "hentpant", category: "ListingPhotoService")
    private let bucketName = "listing-photos"

    func makeUploadPlan(listingId: UUID, images: [ProcessedListingImage]) -> [ListingPhotoUploadPlan] {
        let listingPathComponent = listingId.uuidString.lowercased()
        return images.prefix(3).map { image in
            ListingPhotoUploadPlan(
                path: "\(listingPathComponent)/\(UUID().uuidString.lowercased()).\(image.fileExtension)",
                image: image
            )
        }
    }

    func uploadPhotos(_ plan: [ListingPhotoUploadPlan]) async throws -> [String] {
        let bucket = supabase.storage.from(bucketName)
        var uploadedPaths: [String] = []

        do {
            for upload in plan {
                logger.debug(
                    "Uploading listing photo path=\(upload.path, privacy: .public) mime=\(upload.image.mimeType, privacy: .public) bytes=\(upload.image.data.count)"
                )
                _ = try await bucket.upload(
                    upload.path,
                    data: upload.image.data,
                    options: FileOptions(contentType: upload.image.mimeType, upsert: true)
                )
                logger.debug("Uploaded listing photo path=\(upload.path, privacy: .public)")
                uploadedPaths.append(upload.path)
            }
            return uploadedPaths
        } catch {
            if !uploadedPaths.isEmpty {
                logger.error("Listing photo upload failed after \(uploadedPaths.count) uploads: \(error.localizedDescription, privacy: .public)")
                try? await delete(paths: uploadedPaths)
            } else {
                logger.error("Listing photo upload failed before any uploads completed: \(error.localizedDescription, privacy: .public)")
            }
            throw error
        }
    }

    func publicURLs(for paths: [String]) throws -> [URL] {
        let bucket = supabase.storage.from(bucketName)
        return try paths.map { path in
            let url = try bucket.getPublicURL(path: path)
            logger.debug("Resolved listing photo public URL path=\(path, privacy: .public) url=\(url.absoluteString, privacy: .public)")
            return url
        }
    }

    func deletePhotos(paths: [String]) async throws {
        try await delete(paths: paths)
    }

    private func delete(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        logger.debug("Cleaning up \(paths.count) uploaded listing photos")
        _ = try await supabase.storage.from(bucketName).remove(paths: paths)
    }
}
