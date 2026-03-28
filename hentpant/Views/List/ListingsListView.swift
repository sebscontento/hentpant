//
//  ListingsListView.swift
//  hentpant
//

import CoreLocation
import SwiftUI

struct ListingsListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var location = LocationManager()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(sortedOpen()) { listing in
                    NavigationLink(value: listing.id) {
                        ListingRowView(listing: listing, userCoordinate: location.lastLocation?.coordinate)
                    }
                }
            }
            .navigationTitle(String(localized: "Open listings"))
            .navigationDestination(for: UUID.self) { id in
                ListingDetailView(listingId: id)
            }
            .onAppear {
                location.requestWhenInUse()
                location.start()
            }
        }
    }

    private func sortedOpen() -> [Listing] {
        let open = appState.openListings()
        guard let u = location.lastLocation?.coordinate else {
            return open.sorted { $0.createdAt > $1.createdAt }
        }
        return open.sorted {
            $0.distanceMeters(from: u) < $1.distanceMeters(from: u)
        }
    }
}

private struct ListingRowView: View {
    @EnvironmentObject private var appState: AppState
    let listing: Listing
    let userCoordinate: CLLocationCoordinate2D?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(listing.quantityText)
                    .font(.headline)
                Text(listing.bagSize.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(listing.status.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    if let u = userCoordinate {
                        Text(formatDistance(listing.distanceMeters(from: u)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(relativeTime(listing.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let first = listing.photoData.first {
            PhotoDataImage(data: first)
        } else {
            ZStack {
                Color.green.opacity(0.15)
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            String(format: String(localized: "%lld m"), Int(meters.rounded()))
        } else {
            String(format: String(localized: "%.1f km"), meters / 1000)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    ListingsListView()
        .environmentObject(AppState())
}
