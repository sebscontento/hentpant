//
//  DawaService.swift
//  hentpant
//

import CoreLocation
import Foundation

actor DawaService {
    private let baseURL = URL(string: "https://api.dataforsyningen.dk")!
    private let session: URLSession
    private var autocompleteCache: [String: [DawaAddressSuggestion]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func autocompleteAddresses(query: String, limit: Int = 6) async throws -> [DawaAddressSuggestion] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedQuery.count >= 3 else { return [] }

        if let cached = autocompleteCache[normalizedQuery] {
            return Array(cached.prefix(limit))
        }

        var components = URLComponents(
            url: baseURL.appending(path: "adresser/autocomplete"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: query.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "per_side", value: String(limit)),
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            throw URLError(.badServerResponse)
        }

        let suggestions = try JSONDecoder().decode([DawaAddressSuggestion].self, from: data)
        autocompleteCache[normalizedQuery] = suggestions
        return suggestions
    }

    private var userAgent: String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "hentpant"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "\(bundleIdentifier)/\(version) (iOS)"
    }
}

struct DawaAddressSuggestion: Decodable, Equatable, Identifiable, Sendable {
    let tekst: String
    let adresse: DawaAutocompleteAddress

    var id: String { adresse.id }

    var title: String {
        [adresse.vejnavn, adresse.husnr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var subtitle: String {
        [adresse.postnr, adresse.postnrnavn]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // DAWA autocomplete returns WGS84 coordinates as x=longitude, y=latitude.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: adresse.y, longitude: adresse.x)
    }
}

struct DawaAutocompleteAddress: Decodable, Equatable, Sendable {
    let id: String
    let vejnavn: String
    let husnr: String
    let postnr: String
    let postnrnavn: String
    let x: Double
    let y: Double
}
