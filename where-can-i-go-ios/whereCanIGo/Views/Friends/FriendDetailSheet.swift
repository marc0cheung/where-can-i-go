import SwiftUI

/// Read-only view of a friend's last received card.
struct FriendDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var friendStore: FriendStore
    @Environment(\.dismiss) private var dismiss

    let friendID: String

    @State private var segment: TravelsSegment = .been
    @State private var path: [FriendCountryRoute] = []
    @State private var editingNickname = false
    @State private var nicknameDraft = ""
    @State private var showSafetyCode = false
    @State private var confirmRemove = false
    @State private var errorMessage: String?

    private var friend: Friend? { friendStore.friend(id: friendID) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let friend {
                    content(friend)
                } else {
                    ContentUnavailableView("Friend Removed", systemImage: "person.crop.circle.badge.xmark")
                }
            }
            .navigationTitle(friend?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if friend != nil { menu }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: FriendCountryRoute.self) { route in
                if let friend {
                    FriendCountryRecordsView(card: friend.card, route: route)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Nickname", isPresented: $editingNickname) {
            TextField("Nickname", text: $nicknameDraft)
            Button("Save") { run { try friendStore.setNickname(nicknameDraft, for: friendID) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only you see this name. New cards from this friend keep it.")
        }
        .alert("Safety Code", isPresented: $showSafetyCode) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Compare this code with the one in your friend's Sharing settings. Matching codes mean the cards came from their device.\n\n\(friend?.safetyCode ?? "")")
        }
        .confirmationDialog("Remove \(friend?.name ?? "")?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Friend", role: .destructive) {
                run {
                    try friendStore.remove(id: friendID)
                    dismiss()
                }
            }
        } message: {
            Text("This deletes their card from this device. Your friend isn't notified, and they keep any card you shared.")
        }
        .alert("Couldn't Save", isPresented: Binding {
            errorMessage != nil
        } set: { if !$0 { errorMessage = nil } }) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var menu: some View {
        Menu {
            Button {
                nicknameDraft = friend?.nickname ?? ""
                editingNickname = true
            } label: {
                Label("Set Nickname", systemImage: "pencil")
            }
            Button {
                showSafetyCode = true
            } label: {
                Label("Show Safety Code", systemImage: "checkmark.shield")
            }
            Button(role: .destructive) {
                confirmRemove = true
            } label: {
                Label("Remove Friend", systemImage: "person.badge.minus")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("More"))
    }

    private func content(_ friend: Friend) -> some View {
        List {
            VStack(alignment: .leading, spacing: 16) {
                FriendHeader(
                    photoData: friend.card.photo,
                    title: friend.name,
                    subtitle: TravelCardText.lastReceived(friend.lastReceivedAt),
                    caption: friend.nickname == nil ? nil
                        : String(localized: "Shared as \(friend.card.displayName)"))

                Picker("Travel view", selection: $segment) {
                    Text("Been").tag(TravelsSegment.been)
                    Text("Wishlist").tag(TravelsSegment.wishlist)
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 8)
            .cardListRow()

            if segment == .wishlist {
                wishlistContent(friend.card)
            } else {
                beenContent(friend.card)
            }
        }
        .cardListStyle()
    }

    // MARK: Been

    @ViewBuilder
    private func beenContent(_ card: TravelCardPayload) -> some View {
        if let visits = card.been {
            if visits.isEmpty {
                placeholder(systemImage: "airplane.departure",
                            title: "No trips on this card",
                            message: "\(card.displayName) shares Been records and hasn't logged any yet.")
            } else {
                TravelSummaryCard(
                    stats: TravelStats(
                        records: visits.map {
                            TravelStats.Record(countryCode: $0.countryCode, days: $0.dayCount, startDate: $0.start)
                        },
                        countries: appState.countries),
                    showsChevron: false)
                    .frame(minHeight: 200)
                    .cardListRow()
                countryRows(codes: visits.map(\.countryCode), wishlist: false)
            }
        } else {
            placeholder(systemImage: "eye.slash",
                        title: "Been not shared",
                        message: "\(card.displayName) didn't include Been records in this card.")
        }
    }

    // MARK: Wishlist

    @ViewBuilder
    private func wishlistContent(_ card: TravelCardPayload) -> some View {
        if let plans = card.wishlist {
            if plans.isEmpty {
                placeholder(systemImage: "heart.text.clipboard",
                            title: "No trips on this card",
                            message: "\(card.displayName) shares the Wishlist and hasn't added any trips yet.")
            } else {
                WishlistSummaryCard(stats: WishlistStats(trips: plans.map(\.plannedTrip),
                                                         countries: appState.countries))
                    .frame(minHeight: 200)
                    .cardListRow()
                countryRows(codes: plans.map(\.countryCode), wishlist: true)
            }
        } else {
            placeholder(systemImage: "eye.slash",
                        title: "Wishlist not shared",
                        message: "\(card.displayName) didn't include the Wishlist in this card.")
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func countryRows(codes: [String], wishlist: Bool) -> some View {
        let counts = Dictionary(codes.map { ($0, 1) }, uniquingKeysWith: +)
        let countries = counts.keys.compactMap { appState.country(for: $0) }.sorted {
            $0.localizedName().localizedStandardCompare($1.localizedName()) == .orderedAscending
        }
        Text("Countries")
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .cardListRow()
        ForEach(countries) { country in
            Button {
                path.append(FriendCountryRoute(countryCode: country.code, wishlist: wishlist))
            } label: {
                TravelCountryRow(
                    country: country,
                    tripCount: counts[country.code] ?? 0,
                    showsVisitedBefore: wishlist && appState.visitedCountryCodes.contains(country.code))
            }
            .buttonStyle(.plain)
            .cardListRow()
        }
    }

    private func placeholder(systemImage: String, title: LocalizedStringKey,
                             message: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .cardListRow()
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}

struct FriendCountryRoute: Hashable {
    let countryCode: String
    let wishlist: Bool
}

/// A friend's records for one country.
private struct FriendCountryRecordsView: View {
    @EnvironmentObject private var appState: AppState
    let card: TravelCardPayload
    let route: FriendCountryRoute

    private var country: Country? { appState.country(for: route.countryCode) }
    private var countryName: String { country?.localizedName() ?? route.countryCode }

    private var rows: [RecordRow] {
        if route.wishlist {
            return (card.wishlist ?? []).filter { $0.countryCode == route.countryCode }
                .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
                .map { plan in
                    RecordRow(location: plan.location, purpose: plan.purposeValue,
                              detail: plan.start != nil || plan.end != nil
                              ? TravelFormat.dateRange(start: plan.start, end: plan.end)
                              : plan.days.map { String(localized: "\($0) estimated days") })
                }
        }
        return (card.been ?? []).filter { $0.countryCode == route.countryCode }
            .sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
            .map { visit in
                RecordRow(location: visit.location, purpose: visit.purposeValue,
                          detail: visit.start != nil || visit.end != nil
                          ? TravelFormat.dateRange(start: visit.start, end: visit.end)
                          : visit.dayCount.map { String(localized: "\($0) days") })
            }
    }

    var body: some View {
        List {
            HStack(spacing: 14) {
                Text(country?.flag ?? "").font(.system(size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: countryName).font(.title3.bold())
                    Text(TravelCardText.count(rows.count, wishlist: route.wishlist))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .cardListRow()

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                recordRow(row).cardListRow()
            }
        }
        .cardListStyle()
        .navigationTitle(Text(verbatim: countryName))
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct RecordRow {
        let location: String?
        let purpose: VisitPurpose?
        let detail: String?
    }

    private func recordRow(_ row: RecordRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.purpose?.systemImage ?? (route.wishlist ? "heart" : "mappin.and.ellipse"))
                .foregroundStyle(row.purpose?.color ?? .secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: row.location ?? countryName).font(.subheadline.weight(.semibold))
                if let detail = row.detail {
                    Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
                }
                if let purpose = row.purpose {
                    Text(purpose.localizedDisplayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(purpose.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
