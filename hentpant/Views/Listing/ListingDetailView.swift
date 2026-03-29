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
        .onDisappear {
            location.stop()
        }
    }

    @ViewBuilder
    private func content(for listing: Listing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoStrip(listing)
                meta(listing)
                if listing.isClaimable(by: appState.session) {
                    claimSliderCard(listing)
                }
                if let counterpart = counterpartProfile(for: listing) {
                    contactCard(for: counterpart, listing: listing)
                }
                journeyCard(listing)
                mapPreview(listing)
                actions(listing)
            }
            .padding()
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(
                title: String(localized: "Report listing"),
                onSubmit: { reason in
                    Task { @MainActor in
                        let didSubmit = await appState.submitReport(
                            target: .listing,
                            targetId: listing.id.uuidString,
                            reason: reason
                        )
                        if didSubmit {
                            showReport = false
                        }
                    }
                },
                onCancel: { showReport = false }
            )
        }
        .sheet(isPresented: $showRate) {
            if let other = appState.needsRatingPrompt(for: listing.id) {
                RatingSheet(
                    otherUser: other,
                    onSubmit: { stars, comment in
                        Task { @MainActor in
                            let didSubmit = await appState.submitRating(
                                listingId: listing.id,
                                toUserId: other.id,
                                stars: stars,
                                comment: comment
                            )
                            if didSubmit {
                                showRate = false
                            }
                        }
                    },
                    onSkip: { showRate = false }
                )
            }
        }
        .alert(String(localized: "Remove listing"), isPresented: $showModDelete) {
            TextField(String(localized: "Reason"), text: $modReason)
            Button(String(localized: "Remove"), role: .destructive) {
                Task {
                    await appState.deleteListing(listing.id, reason: modReason.nilIfEmpty)
                    modReason = ""
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This listing will be hidden from the map for everyone."))
        }
    }

    private func contactCard(for user: UserProfile, listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Pickup contact"))
                .font(.headline)

            Text(contactTitle(for: listing, otherUser: user))
                .font(.subheadline.weight(.semibold))

            Text(user.email)
                .font(.body.monospaced())
                .textSelection(.enabled)

            Text(String(localized: "Contact details are only shown once the listing is pending pickup."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func journeyCard(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Journey"))
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(journeySteps(for: listing)) { step in
                    JourneyStatusRow(step: step)
                }
            }

            Label(journeyHeadline(for: listing), systemImage: journeySymbol(for: listing))
                .font(.subheadline.weight(.semibold))

            Text(journeyDetail(for: listing))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func claimSliderCard(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Claim this pickup"), systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                Spacer()
                Text("+50 pts")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: Capsule())
            }

            Text(
                String(
                    localized: "Slide to claim this pickup. The listing will switch to pending pickup and only you and the giver will see the contact details."
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            SlideActionControl(
                title: String(localized: "Slide to claim pickup"),
                tint: .green,
                isLoading: appState.isListingActionInFlight(listing.id)
            ) {
                Task { await appState.claimListing(listing.id) }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func photoStrip(_ listing: Listing) -> some View {
        Group {
            if listing.photoUrls.isEmpty && listing.photoData.isEmpty {
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
                    if !listing.photoUrls.isEmpty {
                        ForEach(Array(listing.photoUrls.enumerated()), id: \.offset) { _, url in
                            RemoteListingImageView(url: url, style: .detail)
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    } else {
                        ForEach(Array(listing.photoData.enumerated()), id: \.offset) { _, data in
                            PhotoDataImage(data: data)
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
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
                Text(listing.statusDisplay(for: appState.session?.id))
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

            if let collectorId = listing.collectorId,
               listing.status == .pendingPickup || listing.status == .completed
            {
                Text(collectorLine(for: collectorId, listing: listing))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
        let actionInFlight = appState.isListingActionInFlight(listing.id)

        VStack(spacing: 12) {
            if let guidance = actionGuidance(for: listing) {
                Label(guidance, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if session?.id == listing.collectorId, listing.status == .pendingPickup {
                VStack(spacing: 8) {
                    Button {
                        Task { await appState.markListingDone(listing.id) }
                    }
                    label: {
                        actionLabel(
                            title: String(localized: "Mark as Done"),
                            isLoading: actionInFlight
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(actionInFlight)

                    Label("+50 pts when pickup is confirmed by giver", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if session?.id == listing.giverId, listing.status == .pendingPickup {
                VStack(spacing: 8) {
                    Button {
                        Task { await appState.releaseListingClaim(listing.id) }
                    }
                    label: {
                        actionLabel(
                            title: String(localized: "Make Available Again"),
                            isLoading: actionInFlight
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(actionInFlight)

                    Label("+25 pts once the receiver marks pickup done", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if session?.id == listing.collectorId, listing.status == .pendingPickup {
                Button(String(localized: "Cancel Claim"), role: .destructive) {
                    Task { await appState.releaseListingClaim(listing.id) }
                }
                .buttonStyle(.bordered)
                .disabled(actionInFlight)
                .frame(maxWidth: .infinity)
            } else if session?.canClaimPant == false,
                      session?.id != listing.giverId,
                      listing.status == .available {
                Label(
                    String(localized: "Enable the receiver role in Profile to claim listings."),
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            if session?.canDeleteAnyListing == true, listing.status != .removed {
                Button(String(localized: "Remove listing (moderator)"), role: .destructive) {
                    showModDelete = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func actionLabel(title: String, isLoading: Bool) -> some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            Text(title)
                .frame(maxWidth: .infinity)
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

    private func actionGuidance(for listing: Listing) -> String? {
        let session = appState.session

        if listing.status == .available, session?.id == listing.giverId {
            return String(localized: "Your listing is live. A receiver can claim it from the map or list.")
        }

        if listing.status == .pendingPickup, session?.id == listing.collectorId {
            return String(localized: "You claimed this item. It is now pending pickup. Use the contact details above to coordinate pickup, then mark it done.")
        }

        if listing.status == .pendingPickup, session?.id == listing.giverId {
            return String(localized: "A receiver claimed your item. It is now pending pickup, and you can make it available again if plans change.")
        }

        if listing.status == .completed {
            return String(localized: "This giveaway is complete.")
        }

        if listing.status == .pendingPickup {
            return String(localized: "This listing is already pending pickup.")
        }

        return nil
    }

    private func journeySteps(for listing: Listing) -> [JourneyStep] {
        [
            JourneyStep(
                title: String(localized: "Published"),
                detail: String(localized: "Live on the map and list."),
                state: .complete
            ),
            JourneyStep(
                title: String(localized: "Pending pickup"),
                detail: String(localized: "A receiver has claimed the item."),
                state: claimStepState(for: listing)
            ),
            JourneyStep(
                title: String(localized: "Completed"),
                detail: String(localized: "The receiver marks pickup as done."),
                state: completionStepState(for: listing)
            ),
        ]
    }

    private func claimStepState(for listing: Listing) -> JourneyStep.State {
        switch listing.status {
        case .available:
            return .upcoming
        case .pendingPickup, .completed:
            return .complete
        case .removed:
            return .upcoming
        }
    }

    private func completionStepState(for listing: Listing) -> JourneyStep.State {
        switch listing.status {
        case .completed:
            return .complete
        case .pendingPickup:
            return .current
        case .available, .removed:
            return .upcoming
        }
    }

    private func journeyHeadline(for listing: Listing) -> String {
        let session = appState.session

        if listing.status == .available, listing.isClaimable(by: session) {
            return String(localized: "Ready to claim pickup")
        }
        if listing.status == .available, session?.id == listing.giverId {
            return String(localized: "Waiting for a receiver")
        }
        if listing.status == .available {
            return String(localized: "Available now")
        }
        if listing.status == .pendingPickup, session?.id == listing.collectorId {
            return String(localized: "Pending pickup for you")
        }
        if listing.status == .pendingPickup, session?.id == listing.giverId {
            return String(localized: "Pending pickup")
        }
        if listing.status == .completed {
            return String(localized: "Journey complete")
        }
        return listing.statusDisplay(for: session?.id)
    }

    private func journeyDetail(for listing: Listing) -> String {
        let session = appState.session

        if listing.status == .available, listing.isClaimable(by: session) {
            return String(localized: "Claim this pickup to move the listing into pending pickup. Nobody else will be able to take it once you do.")
        }
        if listing.status == .available, session?.id == listing.giverId {
            return String(localized: "Receivers can now discover this listing and claim it. You can return here if you need to make it available again.")
        }
        if listing.status == .available {
            return String(localized: "This listing is live and waiting for a receiver to claim it.")
        }
        if listing.status == .pendingPickup, session?.id == listing.collectorId {
            return String(localized: "After you pick up the item, tap \"Mark as Done\" to complete the listing.")
        }
        if listing.status == .pendingPickup, session?.id == listing.giverId {
            return String(localized: "Your item has been claimed. It is now pending pickup while the receiver coordinates collection and marks it done afterward.")
        }
        if listing.status == .completed {
            return String(localized: "This listing has finished successfully. If the rating button is shown below, you can leave feedback now.")
        }
        return String(localized: "Follow the steps below to move this listing through the flow.")
    }

    private func journeySymbol(for listing: Listing) -> String {
        switch listing.status {
        case .available:
            return listing.isClaimable(by: appState.session) ? "hand.raised.fill" : "clock"
        case .pendingPickup:
            return appState.session?.id == listing.collectorId ? "bag.fill.badge.plus" : "clock.badge.checkmark"
        case .completed:
            return "checkmark.circle.fill"
        case .removed:
            return "trash"
        }
    }

    private func collectorLine(for collectorId: String, listing: Listing) -> String {
        let name = appState.displayName(for: collectorId)
        if appState.session?.id == listing.giverId {
            switch listing.status {
            case .pendingPickup:
                return String(localized: "Pending pickup with \(name)")
            case .completed:
                return String(localized: "Picked up by \(name)")
            case .available, .removed:
                return ""
            }
        }

        if appState.session?.id == collectorId {
            switch listing.status {
            case .pendingPickup:
                return String(localized: "Pending pickup from \(appState.displayName(for: listing.giverId))")
            case .completed:
                return String(localized: "You picked this up from \(appState.displayName(for: listing.giverId))")
            case .available, .removed:
                return ""
            }
        }

        return String(localized: "Pending pickup with \(name)")
    }

    private func counterpartProfile(for listing: Listing) -> UserProfile? {
        guard listing.status == .pendingPickup || listing.status == .completed else { return nil }
        guard let otherId = listing.counterpartUserId(for: appState.session?.id) else { return nil }
        return appState.profile(id: otherId)
    }

    private func contactTitle(for listing: Listing, otherUser: UserProfile) -> String {
        if listing.giverId == appState.session?.id {
            return String(localized: "Receiver: \(otherUser.displayName)")
        }
        if listing.collectorId == appState.session?.id {
            return String(localized: "Giver: \(otherUser.displayName)")
        }
        return otherUser.displayName
    }
}

private struct JourneyStep: Identifiable {
    enum State {
        case complete
        case current
        case upcoming

        var icon: String {
            switch self {
            case .complete:
                return "checkmark.circle.fill"
            case .current:
                return "arrow.right.circle.fill"
            case .upcoming:
                return "circle"
            }
        }

        var tint: Color {
            switch self {
            case .complete:
                return .green
            case .current:
                return .blue
            case .upcoming:
                return .secondary
            }
        }
    }

    let id = UUID()
    let title: String
    let detail: String
    let state: State
}

private struct JourneyStatusRow: View {
    let step: JourneyStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.state.icon)
                .foregroundStyle(step.state.tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                Text(step.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SlideActionControl: View {
    let title: String
    let tint: Color
    let isLoading: Bool
    let onComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var didTrigger = false

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset: CGFloat = 4
            let knobSize = max(48, proxy.size.height - (horizontalInset * 2))
            let maxOffset = max(0, proxy.size.width - knobSize - (horizontalInset * 2))
            let progress = maxOffset > 0 ? min(dragOffset / maxOffset, 1) : 0
            let threshold = maxOffset * 0.72

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))

                Capsule()
                    .fill(tint.opacity(0.22))
                    .frame(width: knobSize + dragOffset + (horizontalInset * 2))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .opacity(isLoading ? 0 : max(0.25, 1 - (progress * 0.8)))

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(tint)
                        Spacer()
                    }
                }

                Circle()
                    .fill(tint.gradient)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "chevron.right.2")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: dragOffset + horizontalInset)
                    .shadow(color: tint.opacity(0.22), radius: 8, y: 4)
            }
            .frame(height: proxy.size.height)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isLoading else { return }
                        dragOffset = min(max(0, value.translation.width), maxOffset)
                    }
                    .onEnded { _ in
                        guard !isLoading else { return }
                        if dragOffset >= threshold {
                            didTrigger = true
                            withAnimation(.easeOut(duration: 0.18)) {
                                dragOffset = maxOffset
                            }
                            onComplete()
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityHint(Text(String(localized: "Slide right to confirm this action.")))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard !isLoading else { return }
                didTrigger = true
                withAnimation(.easeOut(duration: 0.18)) {
                    dragOffset = maxOffset
                }
                onComplete()
            }
            .onChange(of: isLoading) { wasLoading, nowLoading in
                guard wasLoading, !nowLoading, didTrigger else { return }
                didTrigger = false
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    dragOffset = 0
                }
            }
        }
        .frame(height: 60)
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
                    Button(String(localized: "Cancel")) {
                        completeAfterKeyboardDismiss {
                            onCancel()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Submit")) {
                        let currentReason = reason
                        completeAfterKeyboardDismiss {
                            onSubmit(currentReason)
                        }
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                focused = true
            }
            .onDisappear {
                focused = false
            }
        }
    }

    private func completeAfterKeyboardDismiss(_ action: @escaping () -> Void) {
        focused = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(75))
            action()
        }
    }
}

private struct RatingSheet: View {
    let otherUser: UserProfile
    let onSubmit: (Int, String?) -> Void
    let onSkip: () -> Void
    @State private var stars = 5
    @State private var comment = ""
    @FocusState private var commentFocused: Bool

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
                        .focused($commentFocused)
                }
            }
            .navigationTitle(String(localized: "Rating"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Skip")) {
                        completeAfterKeyboardDismiss {
                            onSkip()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Submit")) {
                        let currentStars = stars
                        let currentComment = comment.nilIfEmpty
                        completeAfterKeyboardDismiss {
                            onSubmit(currentStars, currentComment)
                        }
                    }
                }
            }
            .onDisappear {
                commentFocused = false
            }
        }
    }

    private func completeAfterKeyboardDismiss(_ action: @escaping () -> Void) {
        commentFocused = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(75))
            action()
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
    .environmentObject(AppState(skipAuthListener: true))
}
