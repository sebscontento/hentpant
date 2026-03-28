//
//  CreateListingView.swift
//  hentpant
//

import MapKit
import PhotosUI
import SwiftUI

struct CreateListingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var location = LocationManager()
    @State private var picks: [PhotosPickerItem] = []
    @State private var photoData: [Data] = []
    @State private var quantity = ""
    @State private var bagSize: BagSize = .medium
    @State private var detail = ""
    @State private var pin = CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683)
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var body: some View {
        NavigationStack {
            Form {
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

                    if !photoData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(photoData.enumerated()), id: \.offset) { _, data in
                                    PhotoDataImage(data: data)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField(String(localized: "Quantity (e.g. ~20 bottles)"), text: $quantity)
                    Picker(String(localized: "Bag size"), selection: $bagSize) {
                        ForEach(BagSize.allCases) { b in
                            Text(b.displayName).tag(b)
                        }
                    }
                    TextField(String(localized: "Optional description (bench, gate, …)"), text: $detail, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    mapPicker
                } header: {
                    Text(String(localized: "Approximate pickup pin"))
                } footer: {
                    Text(String(localized: "Tap the map to move the pin away from your exact address if you prefer."))
                }

                Section {
                    Button(String(localized: "Post listing")) {
                        submit()
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle(String(localized: "Post pant"))
        }
        .onAppear {
            location.requestWhenInUse()
            location.start()
            if let c = location.lastLocation?.coordinate {
                pin = c
                camera = .region(
                    MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
                )
            }
        }
    }

    private var canSubmit: Bool {
        !quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mapPicker: some View {
        MapReader { proxy in
            Map(position: $camera) {
                Annotation(String(localized: "Pickup"), coordinate: pin) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                        .shadow(radius: 2)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { position in
                if let coord = proxy.convert(position, from: .local) {
                    pin = coord
                }
            }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var next: [Data] = []
        for item in items.prefix(3) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                next.append(data)
            }
        }
        await MainActor.run {
            photoData = next
        }
    }

    private func submit() {
        let q = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        appState.createListing(
            photoData: photoData,
            quantityText: q,
            bagSize: bagSize,
            latitude: pin.latitude,
            longitude: pin.longitude,
            detail: detail
        )
        picks = []
        photoData = []
        quantity = ""
        detail = ""
    }
}

#Preview {
    CreateListingView()
        .environmentObject(AppState())
}
