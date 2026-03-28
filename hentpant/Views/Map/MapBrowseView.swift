//
//  MapBrowseView.swift
//  hentpant
//

import MapKit
import SwiftUI

struct MapBrowseView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var location = LocationManager()
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    )
    @State private var selectedListing: Listing?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $camera) {
                    ForEach(appState.openListings()) { listing in
                        Annotation(listing.quantityText, coordinate: listing.coordinate) {
                            Button {
                                selectedListing = listing
                            } label: {
                                Image(systemName: "leaf.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, statusColor(listing.status))
                                    .font(.title2)
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(listing.quantityText)
                        }
                    }
                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .onAppear {
                    location.requestWhenInUse()
                    location.start()
                }

                Button {
                    centerOnUser()
                } label: {
                    Image(systemName: "location.fill")
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                }
                .padding()
                .accessibilityLabel(String(localized: "Center on my location"))
            }
            .navigationTitle(String(localized: "Nearby pant"))
            .sheet(item: $selectedListing) { listing in
                NavigationStack {
                    ListingDetailView(listingId: listing.id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(String(localized: "Close")) {
                                    selectedListing = nil
                                }
                            }
                        }
                }
                .environmentObject(appState)
            }
        }
    }

    private func centerOnUser() {
        guard let c = location.lastLocation?.coordinate else {
            location.requestWhenInUse()
            return
        }
        withAnimation {
            camera = .region(
                MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
            )
        }
    }

    private func statusColor(_ status: ListingStatus) -> Color {
        switch status {
        case .available: return .green
        case .reserved: return .orange
        case .awaitingGiverConfirmation: return .blue
        case .completed, .removed: return .gray
        }
    }
}

#Preview {
    MapBrowseView()
        .environmentObject(AppState())
}
