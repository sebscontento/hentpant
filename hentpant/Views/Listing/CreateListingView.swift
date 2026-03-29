//
//  CreateListingView.swift
//  hentpant
//

import MapKit
import PhotosUI
import SwiftUI

struct CreateListingView: View {
    private static let defaultCoordinate = CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683)

    @EnvironmentObject private var appState: AppState
    @StateObject private var location = LocationManager()
    @StateObject private var addressSearch = MapAddressSearchModel()
    @FocusState private var isAddressFieldFocused: Bool
    private let imageProcessor = ListingImageProcessor()

    @State private var picks: [PhotosPickerItem] = []
    @State private var photos: [ProcessedListingImage] = []
    @State private var quantity = ""
    @State private var bagSize: BagSize = .medium
    @State private var detail = ""
    @State private var photoSelectionError: String?
    @State private var pin = Self.defaultCoordinate
    @State private var selectedSearchAddressLabel: String?
    @State private var hasSeededPinFromLocation = false
    @State private var hasMovedPinManually = false
    @State private var lastAppliedPrefillId: UUID?
    @State private var isSubmitting = false
    @State private var showPostedConfirmation = false
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: Self.defaultCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    JourneyChecklistRow(
                        title: String(localized: "1. Add photos"),
                        detail: photos.isEmpty
                            ? String(localized: "Required before publishing.")
                            : String(localized: "\(photos.count) photo(s) ready."),
                        state: photos.isEmpty ? .needed : .ready
                    )

                    JourneyChecklistRow(
                        title: String(localized: "2. Describe the item"),
                        detail: hasRequiredDescription
                            ? String(localized: "Description and pickup notes are ready.")
                            : String(localized: "Add item details and pickup notes before publishing."),
                        state: hasRequiredDescription ? .ready : .needed
                    )

                    JourneyChecklistRow(
                        title: String(localized: "3. Set an approximate pin"),
                        detail: locationStatusText,
                        state: hasMovedPinManually || hasSeededPinFromLocation ? .ready : .needed
                    )
                } header: {
                    Text(String(localized: "Posting journey"))
                } footer: {
                    Text(String(localized: "Your listing goes live as available as soon as you publish it."))
                }

                Section {
                    PhotosPicker(
                        selection: $picks,
                        maxSelectionCount: 3,
                        matching: .images
                    ) {
                        Label(String(localized: "Add photos (max 3)"), systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: picks) { _, newItems in
                        Task { await loadPhotos(newItems) }
                    }

                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(photos.enumerated()), id: \.offset) { _, image in
                                    PhotoDataImage(data: image.data)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }

                    if let photoSelectionError {
                        Label(photoSelectionError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(String(localized: "Photos"))
                } footer: {
                    Text(String(localized: "At least one photo is required so receivers can see what they are claiming."))
                }

                Section {
                    TextField(String(localized: "Short title (e.g. Bag of pants)"), text: $quantity)
                    Picker(String(localized: "Bag size"), selection: $bagSize) {
                        ForEach(BagSize.allCases) { b in
                            Text(b.displayName).tag(b)
                        }
                    }
                    TextField(String(localized: "Description and pickup notes"), text: $detail, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text(String(localized: "Listing details"))
                }

                Section {
                    mapPicker
                } header: {
                    Text(String(localized: "Approximate pickup pin"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(String(localized: "Tap anywhere on the map to place the pin at that specific location"), systemImage: "mappin.and.ellipse")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.blue)
                            Text(String(localized: "This lets you specify a street corner or exact pickup spot, not just your general address."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        Label(locationStatusText, systemImage: "location.viewfinder")
                        if location.lastLocation != nil {
                            Button(String(localized: "Use my current area")) {
                                movePinToCurrentLocation()
                            }
                        }
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(String(localized: "Publish listing"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit || isSubmitting)
                }
            }
            .navigationTitle(String(localized: "Give away"))
        }
        .alert(String(localized: "Listing published"), isPresented: $showPostedConfirmation) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "Your item is now live and available for receivers to claim."))
        }
        .onAppear {
            location.requestWhenInUse()
            location.start()
            applyCreateListingPrefillIfNeeded()
            syncPinFromCurrentLocationIfNeeded()
        }
        .onChange(of: appState.createListingPrefill?.id) { _, _ in
            applyCreateListingPrefillIfNeeded()
        }
        .onChange(of: location.lastLocation?.timestamp) { _, _ in
            applyCreateListingPrefillIfNeeded()
            syncPinFromCurrentLocationIfNeeded()
        }
        .onChange(of: isAddressFieldFocused) { _, isFocused in
            if !isFocused {
                addressSearch.dismissSuggestions()
            }
        }
        .onDisappear {
            location.stop()
        }
    }

    private var canSubmit: Bool {
        !photos.isEmpty && !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasRequiredDescription
    }

    private var hasRequiredDescription: Bool {
        !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var locationStatusText: String {
        if selectedSearchAddressLabel != nil {
            return String(localized: "Using the address you selected from the map search.")
        }

        switch location.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if hasMovedPinManually {
                return String(localized: "Custom pin selected.")
            }
            if hasSeededPinFromLocation {
                return String(localized: "Using your current area as the starting pin.")
            }
            return String(localized: "Waiting for your current location. You can still place the pin manually.")
        case .denied, .restricted:
            return String(localized: "Location access is off, so the map stays on Copenhagen until you place the pin manually.")
        case .notDetermined:
            return String(localized: "Allow location to start near you, or keep the Copenhagen default and place the pin manually.")
        @unknown default:
            return String(localized: "If location is unavailable, the map stays on Copenhagen until you place the pin manually.")
        }
    }

    private var addressQueryBinding: Binding<String> {
        Binding(
            get: { addressSearch.query },
            set: { newValue in
                if let currentSelection = selectedSearchAddressLabel, currentSelection != newValue {
                    selectedSearchAddressLabel = nil
                }
                addressSearch.setQuery(newValue)
            }
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

    private var mapPicker: some View {
        VStack(spacing: 12) {
            addressSearchPanel

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(String(localized: "Tap any spot on the map to place your pin"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                MapReader { proxy in
                    Map(position: $camera) {
                        Annotation(String(localized: "Pickup"), coordinate: pin) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                                .shadow(radius: 2)
                        }

                        UserAnnotation()
                    }
                        .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        Button {
                            centerOnUser()
                        } label: {
                            Image(systemName: "location.fill")
                                .padding(10)
                                .background(.thinMaterial, in: Circle())
                        }
                        .padding(12)
                        .accessibilityLabel(String(localized: "Center on my location"))
                    }
                    .onTapGesture { position in
                        if let coord = proxy.convert(position, from: .local) {
                            clearSelectedSearchAddress()
                            hasMovedPinManually = true
                            hasSeededPinFromLocation = false
                            pin = coord
                        }
                    }
                }
            }
        }
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

            if let selectedSearchAddressLabel {
                Divider()
                selectedAddressSummary(addressLabel: selectedSearchAddressLabel)
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var next: [ProcessedListingImage] = []
        var firstError: String?
        for item in items.prefix(3) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ListingImageProcessingError.loadFailed
                }
                next.append(try imageProcessor.process(data: data))
            } catch {
                if firstError == nil {
                    firstError = error.localizedDescription
                }
            }
        }
        await MainActor.run {
            photos = next
            photoSelectionError = firstError
        }
    }

    private func submit() {
        let q = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let selectedPhotos = photos
        let bag = bagSize
        let lat = pin.latitude
        let lon = pin.longitude
        let desc = detail
        Task {
            await MainActor.run {
                isSubmitting = true
            }
            let didCreate = await appState.createListing(
                photos: selectedPhotos,
                quantityText: q,
                bagSize: bag,
                latitude: lat,
                longitude: lon,
                detail: desc
            )
            await MainActor.run {
                isSubmitting = false
                if didCreate {
                    picks = []
                    photos = []
                    photoSelectionError = nil
                    quantity = ""
                    detail = ""
                    clearAddressSearch()
                    hasMovedPinManually = false
                    hasSeededPinFromLocation = false
                    syncPinFromCurrentLocationIfNeeded()
                    showPostedConfirmation = true
                }
            }
        }
    }

    private func syncPinFromCurrentLocationIfNeeded() {
        guard !hasMovedPinManually, !hasSeededPinFromLocation else { return }
        guard let coordinate = location.lastLocation?.coordinate else { return }

        hasSeededPinFromLocation = true
        pin = coordinate
        focusMap(on: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
    }

    private func applyCreateListingPrefillIfNeeded() {
        guard let prefill = appState.createListingPrefill else { return }
        guard lastAppliedPrefillId != prefill.id else { return }

        lastAppliedPrefillId = prefill.id
        addressSearch.clear()
        isAddressFieldFocused = false
        selectedSearchAddressLabel = prefill.addressLabel
        hasMovedPinManually = true
        hasSeededPinFromLocation = false
        pin = prefill.coordinate
        focusMap(on: prefill.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        appState.clearCreateListingPrefill()
    }

    private func movePinToCurrentLocation() {
        guard let coordinate = location.lastLocation?.coordinate else {
            location.requestWhenInUse()
            return
        }
        clearSelectedSearchAddress()
        hasMovedPinManually = false
        hasSeededPinFromLocation = true
        pin = coordinate
        focusMap(on: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
    }

    private func centerOnUser() {
        guard let coordinate = location.lastLocation?.coordinate else {
            location.requestWhenInUse()
            return
        }
        focusMap(on: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
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
        selectedSearchAddressLabel = suggestion.tekst
        isAddressFieldFocused = false
        hasMovedPinManually = true
        hasSeededPinFromLocation = false
        pin = suggestion.coordinate
        focusMap(on: suggestion.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
    }

    private func clearSelectedSearchAddress() {
        selectedSearchAddressLabel = nil
        addressSearch.clearSelection()
    }

    private func clearAddressSearch() {
        selectedSearchAddressLabel = nil
        addressSearch.clear()
    }
}

private extension CreateListingView {
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
    func selectedAddressSummary(addressLabel: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Selected address"))
                    .font(.subheadline.weight(.semibold))
                Text(addressLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Tap the map if you want to offset the pickup pin from this address."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct JourneyChecklistRow: View {
    enum State {
        case needed
        case optional
        case ready

        var icon: String {
            switch self {
            case .needed:
                return "circle"
            case .optional:
                return "minus.circle"
            case .ready:
                return "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .needed:
                return .orange
            case .optional:
                return .secondary
            case .ready:
                return .green
            }
        }
    }

    let title: String
    let detail: String
    let state: State

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.icon)
                .foregroundStyle(state.tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    CreateListingView()
        .environmentObject(AppState(skipAuthListener: true))
}
