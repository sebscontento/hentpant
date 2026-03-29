//
//  MapBrowseView.swift
//  hentpant
//

import MapKit
import SwiftUI

struct MapBrowseView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var location = LocationManager()
    @StateObject private var addressSearch = MapAddressSearchModel()
    @FocusState private var isAddressFieldFocused: Bool
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
    )
    @State private var selectedListing: Listing?
    @State private var customTappedPin: CLLocationCoordinate2D?
    @State private var showCustomPinMenu = false

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) {
                    ForEach(mapListings) { listing in
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

                    if let selectedAddress = addressSearch.selectedSuggestion {
                        Annotation(String(localized: "Selected address"), coordinate: selectedAddress.coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .blue)
                                .font(.title)
                                .shadow(radius: 2)
                        }
                    }

                    if let customPin = customTappedPin {
                        Annotation(String(localized: "Custom location"), coordinate: customPin) {
                            Image(systemName: "pin.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .purple)
                                .font(.title)
                                .shadow(radius: 2)
                        }
                    }

                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture { position in
                    if let coord = proxy.convert(position, from: .local) {
                        customTappedPin = coord
                        showCustomPinMenu = true
                        isAddressFieldFocused = false
                        addressSearch.dismissSuggestions()
                    }
                }
            }
            .onAppear {
                location.requestWhenInUse()
                location.start()
            }
            .onDisappear {
                location.stop()
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    centerOnUser()
                } label: {
                    Image(systemName: "location.fill")
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                }
                .padding(.top, 12)
                .padding(.trailing)
                .accessibilityLabel(String(localized: "Center on my location"))
            }
            .safeAreaInset(edge: .top, spacing: 12) {
                addressSearchPanel
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            .navigationTitle(String(localized: "Nearby items"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                MapJourneyHint(
                    title: mapHintTitle,
                    message: mapHintMessage,
                    systemImage: mapHintSymbol
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
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
            .confirmationDialog(
                String(localized: "Location on map"),
                isPresented: $showCustomPinMenu,
                presenting: customTappedPin
            ) { pin in
                if appState.session?.canPostPant == true {
                    Button(String(localized: "Create listing here")) {
                        startCreateListing(at: pin)
                    }
                }
                Button(String(localized: "Clear"), role: .destructive) {
                    customTappedPin = nil
                }
            } message: { pin in
                Text(String(localized: "You tapped on (\(String(format: "%.4f", pin.latitude)), \(String(format: "%.4f", pin.longitude)))"))
            }
            .onChange(of: isAddressFieldFocused) { _, isFocused in
                if !isFocused {
                    addressSearch.dismissSuggestions()
                }
            }
        }
    }

    private var mapListings: [Listing] {
        let visible = appState.availableListings() + appState.activeJourneyListings()
        var seen = Set<UUID>()
        return visible.filter { listing in
            seen.insert(listing.id).inserted
        }
    }

    private var mapHintTitle: String {
        if mapListings.isEmpty {
            return String(localized: "Nothing open right now")
        }
        if !appState.activeJourneyListings().isEmpty {
            return String(localized: "Your active items stay visible")
        }
        if appState.session?.canClaimPant == false {
            return String(localized: "Receiver role is off")
        }
        return String(localized: "Tap a pin or the map")
    }

    private var mapHintMessage: String {
        if mapListings.isEmpty {
            return appState.session?.canPostPant == true
                ? String(localized: "Check back soon, or create a listing from the Give Away tab. You can also tap the map to place a listing at a specific location.")
                : String(localized: "Check back soon for new items nearby.")
        }
        if !appState.activeJourneyListings().isEmpty {
            return String(localized: "Available items stay public, while pending pickup ones are only kept on the map for the giver and receiver. Tap the map to place a listing at a specific street corner.")
        }
        if appState.session?.canClaimPant == false {
            return String(localized: "Enable the receiver role in Profile if you want to claim items from the map.")
        }
        return String(localized: "Open any listing to see details, claim it, and mark it done after pickup. Tap the map to place a listing at a specific location.")
    }

    private var mapHintSymbol: String {
        if mapListings.isEmpty {
            return "shippingbox"
        }
        if !appState.activeJourneyListings().isEmpty {
            return "point.topleft.down.curvedto.point.bottomright.up"
        }
        if appState.session?.canClaimPant == false {
            return "person.crop.circle.badge.exclamationmark"
        }
        return "figure.walk.motion"
    }

    private var addressQueryBinding: Binding<String> {
        Binding(
            get: { addressSearch.query },
            set: { addressSearch.setQuery($0) }
        )
    }

    private var shouldShowAddressResults: Bool {
        isAddressFieldFocused && (
            addressSearch.isLoading ||
            !addressSearch.suggestions.isEmpty ||
            addressSearch.errorMessage != nil ||
            addressSearch.showsNoResults
        )
    }

    private var addressSearchPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(String(localized: "Search Danish address"), text: addressQueryBinding)
                    .focused($isAddressFieldFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        submitAddressSearch()
                    }

                if addressSearch.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if !addressSearch.query.isEmpty {
                    Button {
                        clearAddressSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Clear address search"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if shouldShowAddressResults {
                Divider()

                if !addressSearch.suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(addressSearch.suggestions) { suggestion in
                            Button {
                                selectAddress(suggestion)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(.green)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(suggestion.title.isEmpty ? suggestion.tekst : suggestion.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)

                                        if !suggestion.subtitle.isEmpty {
                                            Text(suggestion.subtitle)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        } else if suggestion.title != suggestion.tekst {
                                            Text(suggestion.tekst)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }

                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            if suggestion.id != addressSearch.suggestions.last?.id {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                } else if let errorMessage = addressSearch.errorMessage {
                    addressSearchMessageRow(
                        message: errorMessage,
                        systemImage: "wifi.exclamationmark"
                    )
                } else if addressSearch.showsNoResults {
                    addressSearchMessageRow(
                        message: String(localized: "No matching address found yet."),
                        systemImage: "magnifyingglass"
                    )
                }
            }

            if let selectedAddress = addressSearch.selectedSuggestion {
                Divider()
                selectedAddressCallToAction(selectedAddress)
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private func centerOnUser() {
        guard let c = location.lastLocation?.coordinate else {
            location.requestWhenInUse()
            return
        }
        focusMap(on: c, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
    }

    private func focusMap(on coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        withAnimation {
            camera = .region(MKCoordinateRegion(center: coordinate, span: span))
        }
    }

    private func submitAddressSearch() {
        if let suggestion = addressSearch.suggestions.first {
            selectAddress(suggestion)
        } else {
            isAddressFieldFocused = false
        }
    }

    private func selectAddress(_ suggestion: DawaAddressSuggestion) {
        addressSearch.select(suggestion)
        isAddressFieldFocused = false
        focusMap(on: suggestion.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
    }

    private func startCreateListing(at coordinate: CLLocationCoordinate2D) {
        isAddressFieldFocused = false
        addressSearch.dismissSuggestions()
        customTappedPin = nil
        showCustomPinMenu = false
        appState.beginCreateListing(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            addressLabel: nil
        )
    }

    private func startCreateListingFromAddress(at suggestion: DawaAddressSuggestion) {
        isAddressFieldFocused = false
        addressSearch.dismissSuggestions()
        appState.beginCreateListing(
            latitude: suggestion.coordinate.latitude,
            longitude: suggestion.coordinate.longitude,
            addressLabel: suggestion.tekst
        )
    }

    private func clearAddressSearch() {
        addressSearch.clear()
        isAddressFieldFocused = true
    }

    private func statusColor(_ status: ListingStatus) -> Color {
        switch status {
        case .available: return .green
        case .pendingPickup: return .orange
        case .completed, .removed: return .gray
        }
    }
}

private extension MapBrowseView {
    @ViewBuilder
    func addressSearchMessageRow(message: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    func selectedAddressCallToAction(_ suggestion: DawaAddressSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Selected address"))
                        .font(.subheadline.weight(.semibold))
                    Text(suggestion.tekst)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if appState.session?.canPostPant == true {
                Button {
                    startCreateListingFromAddress(at: suggestion)
                } label: {
                    Label(String(localized: "Create listing here"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label(
                    String(localized: "Enable the giver role in Profile to create a listing at this address."),
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct MapJourneyHint: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.green)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

#Preview {
    MapBrowseView()
        .environmentObject(AppState(skipAuthListener: true))
}
