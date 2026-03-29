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
                if sortedAvailable().isEmpty && sortedActive().isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                } else {
                    if !sortedActive().isEmpty {
                        Section {
                            ForEach(sortedActive()) { listing in
                                listingLink(for: listing)
                            }
                        } header: {
                            Text(String(localized: "Your listings and claims"))
                        } footer: {
                            Text(String(localized: "Listings you published and items waiting for pickup stay here until they are complete or available again."))
                        }
                    }

                    if !sortedAvailable().isEmpty {
                        Section {
                            ForEach(sortedAvailable()) { listing in
                                listingLink(for: listing)
                            }
                        } header: {
                            Text(String(localized: "Available nearby"))
                        } footer: {
                            Text(String(localized: "Only items that are still available to claim are shown here."))
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Listings"))
            .refreshable {
                await appState.refresh()
            }
            .navigationDestination(for: UUID.self) { id in
                ListingDetailView(listingId: id)
            }
            .onAppear {
                location.requestWhenInUse()
                location.start()
            }
            .onDisappear {
                location.stop()
            }
        }
    }

    private func listingLink(for listing: Listing) -> some View {
        NavigationLink(value: listing.id) {
            ListingRowView(listing: listing, userCoordinate: location.lastLocation?.coordinate)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: listing.isClaimable(by: appState.session)) {
            if listing.isClaimable(by: appState.session) {
                Button(String(localized: "Claim pickup")) {
                    Task { await appState.claimListing(listing.id) }
                }
                .tint(.green)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if appState.session?.canClaimPant == false {
            ContentUnavailableView(
                String(localized: "Receiver role is off"),
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text(String(localized: "Turn on \"I claim items\" in Profile to claim items from this screen."))
            )
        } else {
            ContentUnavailableView(
                String(localized: "No available items"),
                systemImage: "shippingbox",
                description: Text(
                    appState.session?.canPostPant == true
                        ? String(localized: "Check back soon, or publish a new listing from the Give Away tab.")
                        : String(localized: "Check back soon for new items nearby.")
                )
            )
        }
    }

    private func sortedAvailable() -> [Listing] {
        let available = appState.availableListings()
        guard let u = location.lastLocation?.coordinate else {
            return available.sorted { $0.createdAt > $1.createdAt }
        }
        return available.sorted {
            $0.distanceMeters(from: u) < $1.distanceMeters(from: u)
        }
    }

    private func sortedActive() -> [Listing] {
        let userId = appState.session?.id
        return appState.activeJourneyListings().sorted { lhs, rhs in
            let lhsPriority = activePriority(for: lhs, userId: userId)
            let rhsPriority = activePriority(for: rhs, userId: userId)

            if lhsPriority == rhsPriority {
                return lhs.createdAt > rhs.createdAt
            }
            return lhsPriority < rhsPriority
        }
    }

    private func activePriority(for listing: Listing, userId: String?) -> Int {
        switch listing.status {
        case .pendingPickup where listing.collectorId == userId:
            return 0
        case .available where listing.giverId == userId:
            return 1
        case .pendingPickup where listing.giverId == userId:
            return 2
        case .pendingPickup:
            return 2
        case .available:
            return 3
        case .completed, .removed:
            return 4
        }
    }
}

private struct ListingRowView: View {
    @EnvironmentObject private var appState: AppState
    let listing: Listing
    let userCoordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                        Text(listing.statusDisplay(for: appState.session?.id))
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
                    if listing.collectorId == appState.session?.id, listing.status == .pendingPickup {
                        Text(String(localized: "This item is pending pickup for you. Open it to coordinate pickup or mark it done."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if listing.isClaimable(by: appState.session) {
                Button {
                    Task { await appState.claimListing(listing.id) }
                } label: {
                    if appState.isListingActionInFlight(listing.id) {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(String(localized: "Claim pickup"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isListingActionInFlight(listing.id))
            } else if listing.isOwned(by: appState.session?.id), listing.status == .available {
                Label(String(localized: "Your listing is live and available."), systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if listing.isOwned(by: appState.session?.id), listing.status == .pendingPickup {
                Label(String(localized: "This item is pending pickup. Open it to see contact details or make it available again."), systemImage: "person.crop.circle.badge.checkmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if listing.collectorId == appState.session?.id, listing.status == .pendingPickup {
                Label(String(localized: "Pickup is pending. Mark it done after pickup, or cancel if plans change."), systemImage: "checklist")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if listing.status == .pendingPickup {
                Label(String(localized: "Pending pickup."), systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(appState.isListingActionInFlight(listing.id) ? 0.65 : 1)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = listing.primaryPhotoURL {
            RemoteListingImageView(url: url, style: .thumbnail)
        } else if let first = listing.photoData.first {
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
        .environmentObject(AppState(skipAuthListener: true))
}
