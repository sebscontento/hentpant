//
//  MapAddressSearchModel.swift
//  hentpant
//

import Foundation

@MainActor
final class MapAddressSearchModel: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var suggestions: [DawaAddressSuggestion] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedSuggestion: DawaAddressSuggestion?

    private let dawaService: DawaService
    private var searchTask: Task<Void, Never>?

    init(dawaService: DawaService = DawaService()) {
        self.dawaService = dawaService
    }

    deinit {
        searchTask?.cancel()
    }

    var showsNoResults: Bool {
        selectedSuggestion == nil && !isLoading && errorMessage == nil && normalizedQuery.count >= 3 && suggestions.isEmpty
    }

    func setQuery(_ newValue: String) {
        query = newValue

        if selectedSuggestion?.tekst != newValue {
            selectedSuggestion = nil
        }

        scheduleSearch(for: newValue)
    }

    func select(_ suggestion: DawaAddressSuggestion) {
        searchTask?.cancel()
        selectedSuggestion = suggestion
        query = suggestion.tekst
        suggestions = []
        errorMessage = nil
        isLoading = false
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        suggestions = []
        errorMessage = nil
        isLoading = false
        selectedSuggestion = nil
    }

    func clearSelection() {
        searchTask?.cancel()
        suggestions = []
        errorMessage = nil
        isLoading = false
        selectedSuggestion = nil
    }

    func dismissSuggestions() {
        searchTask?.cancel()
        suggestions = []
        errorMessage = nil
        isLoading = false
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleSearch(for rawQuery: String) {
        let trimmedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        searchTask?.cancel()
        suggestions = []
        errorMessage = nil

        guard trimmedQuery.count >= 3 else {
            isLoading = false
            return
        }

        isLoading = true
        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }

                let results = try await dawaService.autocompleteAddresses(query: trimmedQuery, limit: 6)
                guard !Task.isCancelled else { return }

                applySearchResults(results, for: trimmedQuery)
            } catch is CancellationError {
                return
            } catch {
                applySearchError(for: trimmedQuery)
            }
        }
    }

    private func applySearchResults(_ results: [DawaAddressSuggestion], for query: String) {
        guard normalizedQuery.caseInsensitiveCompare(query) == .orderedSame else { return }
        suggestions = results
        errorMessage = nil
        isLoading = false
    }

    private func applySearchError(for query: String) {
        guard normalizedQuery.caseInsensitiveCompare(query) == .orderedSame else { return }
        suggestions = []
        errorMessage = String(localized: "Address search is unavailable right now.")
        isLoading = false
    }
}
