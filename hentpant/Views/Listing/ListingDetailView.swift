//
//  ListingDetailView.swift
//  hentpant
//

import MapKit
import SwiftUI

struct ListingDetailView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var location = LocationManager()
    let listingId: UUID

    @State private var showReport = false
    @State private var showRate = false
    @State private var showModDelete = false
    @State private var modReason = ""

    private var listing: Listing? {
        appState.listings.first { $0.id == listingId }
    }

    var body: some View {
        Group {
            if let listing {
                content(for: listing)
            } else {
                ContentUnavailableView(
                    String(localized: "Listing removed"),
                    systemImage: "trash",
                    description: Text(String(localized: "This listing is no longer available."))
                )
            }
        }
        .navigationTitle(String(localized: "Details"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            location.requestWhenInUse()
            location.start()
        }
    }

    @ViewBuilder
    private func content(for listing: Listing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoStrip(listing)
                meta(listing)
                mapPreview(listing)
                actions(listing)
            }
            .padding()
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(
                title: String(localized: "Report listing"),
                onSubmit: { reason in
                    appState.submitReport(target: .listing, targetId: listing.id.uuidString, reason: reason)
                    showReport = false
                },
                onCancel: { showReport = false }
            )
        }
        .sheet(isPresented: $showRate) {
            if let other = appState.needsRatingPrompt(for: listing.id) {
                RatingSheet(
                    otherUser: other,
                    onSubmit: { stars, comment in
                        appState.submitRating(
                            listingId: listing.id,
                            toUserId: other.id,
                            stars: stars,
                            comment: comment
                        )
                        showRate = false
                    },
                    onSkip: { showRate = false }
                )
            }
        }
        .alert(String(localized: "Remove listing"), isPresented: $showModDelete) {
            TextField(String(localized: "Reason"), text: $modReason)
            Button(String(localized: "Remove"), role: .destructive) {
                appState.deleteListing(listing.id, reason: modReason.nilIfEmpty)
                modReason = ""
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This listing will be hidden from the map for everyone."))
        }
    }

    private func photoStrip(_ listing: Listing) -> some View {
        Group {
            if listing.photoData.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green.opacity(0.12))
                    .frame(height: 180)
                    .overlay {
                        Image(systemName: "leaf.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                    }
            } else {
                TabView {
                    ForEach(Array(listing.photoData.enumerated()), id: \.offset) { _, data in
                        PhotoDataImage(data: data)
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(height: 220)
                .tabViewStyle(.page)
            }
        }
    }

    private func meta(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(listing.quantityText)
                .font(.title2.weight(.semibold))
            Text(listing.bagSize.displayName)
                .foregroundStyle(.secondary)
            HStack {
                Text(listing.status.displayName)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                if let u = location.lastLocation?.coordinate {
                    Text(distanceText(from: u, listing: listing))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let detail = listing.detail, !detail.isEmpty {
                Text(detail)
                    .font(.body)
            }
            Text(
                String(
                    localized: "Posted by \(appState.displayName(for: listing.giverId)) · \(relative(listing.createdAt))"
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func mapPreview(_ listing: Listing) -> some View {
        Map(position: .constant(.region(
            MKCoordinateRegion(
                center: listing.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        ))) {
            Annotation(listing.quantityText, coordinate: listing.coordinate) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
            }
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func actions(_ listing: Listing) -> some View {
        let session = appState.session

        VStack(spacing: 12) {
            if session?.canClaimPant == true,
               listing.status == .available,
               listing.giverId != session?.id
            {
                Button(String(localized: "I’ll collect this")) {
                    appState.claimListing(listing.id)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            if session?.id == listing.collectorId, listing.status == .reserved {
                Button(String(localized: "Picked up")) {
                    appState.markPickedUp(listing.id)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            if session?.id == listing.giverId, listing.status == .awaitingGiverConfirmation {
                Button(String(localized: "Confirm bag is gone")) {
                    appState.confirmPickup(listing.id)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            if listing.status == .completed, appState.needsRatingPrompt(for: listing.id) != nil {
                Button(String(localized: "Rate the other person")) {
                    showRate = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            Button(String(localized: "Report")) {
                showReport = true
            }
            .frame(maxWidth: .infinity)

            if session?.canDeleteAnyListing == true, listing.status != .removed {
                Button(String(localized: "Remove listing (moderator)"), role: .destructive) {
                    showModDelete = true
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func distanceText(from user: CLLocationCoordinate2D, listing: Listing) -> String {
        let m = listing.distanceMeters(from: user)
        if m < 1000 {
            return String(format: String(localized: "%lld m away"), Int(m.rounded()))
        }
        return String(format: String(localized: "%.1f km away"), m / 1000)
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

private struct ReportSheet: View {
    let title: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @State private var reason = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "What’s wrong?"), text: $reason, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focused)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Submit")) {
                        onSubmit(reason)
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

private struct RatingSheet: View {
    let otherUser: UserProfile
    let onSubmit: (Int, String?) -> Void
    let onSkip: () -> Void
    @State private var stars = 5
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(localized: "How was your experience with \(otherUser.displayName)?"))
                }
                Section {
                    Picker(String(localized: "Stars"), selection: $stars) {
                        ForEach(1...5, id: \.self) { s in
                            Text("\(s)").tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField(String(localized: "Comment (optional)"), text: $comment, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(String(localized: "Rating"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Skip")) { onSkip() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Submit")) {
                        onSubmit(stars, comment.nilIfEmpty)
                    }
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#Preview {
    NavigationStack {
        ListingDetailView(listingId: UUID())
    }
    .environmentObject(AppState())
}
