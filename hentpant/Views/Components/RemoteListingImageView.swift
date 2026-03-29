//
//  RemoteListingImageView.swift
//  hentpant
//

import OSLog
import SwiftUI

struct RemoteListingImageView: View {
    enum Style {
        case thumbnail
        case detail
    }

    let url: URL
    var style: Style = .thumbnail

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "hentpant", category: "RemoteListingImageView")

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure(let error):
                failedView
                    .onAppear {
                        logger.error("Remote listing image failed url=\(url.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    }
            case .empty:
                loadingView
            @unknown default:
                failedView
            }
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        ZStack {
            Color.green.opacity(0.10)
            ProgressView()
                .tint(.green)
        }
    }

    @ViewBuilder
    private var failedView: some View {
        ZStack {
            Color.orange.opacity(0.14)
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if style == .detail {
                    Text(String(localized: "Image failed to load"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }
}
