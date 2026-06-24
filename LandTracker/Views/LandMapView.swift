import SwiftUI
import SwiftData
import MapKit

struct LandMapView: View {
    @Query private var lands: [Land]
    @Query(sort: \LandGroup.name) private var groups: [LandGroup]
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @State private var position: MapCameraPosition = .region(Self.defaultRegion())
    @State private var selectedParcelID: UUID?
    @State private var selectedGroupID: UUID?
    @State private var expandedGroupIDs: Set<UUID> = []
    @State private var showingAccount = false
    @State private var showingSettings = false

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $position) {
                    ForEach(lands) { land in
                        ForEach(land.catastroRings.indices, id: \.self) { index in
                            let ring = land.catastroRings[index]
                            if !ring.isEmpty {
                                MapPolygon(coordinates: ring.map { $0.clLocation })
                                    .foregroundStyle(color(for: land).opacity(fillOpacity(for: land)))
                                    .stroke(color(for: land), lineWidth: strokeWidth(for: land))
                            }
                        }
                    }
                    ForEach(lands) { land in
                        if land.catastroRings.allSatisfy(\.isEmpty) {
                            MapCircle(center: land.coordinate, radius: 90)
                                .foregroundStyle(color(for: land).opacity(fillOpacity(for: land)))
                                .stroke(color(for: land), lineWidth: strokeWidth(for: land))
                        }
                    }
                }
                .onAppear {
                    moveCamera(to: regionForLands(lands), animated: false)
                }
                .onChange(of: lands) { _, _ in
                    if let selectedParcel {
                        moveCamera(to: regionForLand(selectedParcel))
                    } else if let selectedGroupID,
                              let group = groups.first(where: { $0.id == selectedGroupID }),
                              !group.lands.isEmpty {
                        moveCamera(to: regionForGroup(group))
                    } else {
                        moveCamera(to: regionForLands(lands))
                    }
                }
                .onChange(of: groups) { _, _ in
                    if let selectedParcel {
                        moveCamera(to: regionForLand(selectedParcel))
                    } else if let selectedGroupID,
                              let group = groups.first(where: { $0.id == selectedGroupID }),
                              !group.lands.isEmpty {
                        moveCamera(to: regionForGroup(group))
                    }
                }
                .onChange(of: selectedParcelID) { _, _ in
                    if let selectedParcel {
                        moveCamera(to: regionForLand(selectedParcel))
                    }
                }
                .onChange(of: selectedGroupID) { _, newValue in
                    guard let newValue else { return }
                    if selectedParcelID != nil {
                        expandedGroupIDs.insert(newValue)
                        return
                    }
                    guard let group = groups.first(where: { $0.id == newValue }) else { return }
                    moveCamera(to: regionForGroup(group))
                    expandedGroupIDs.insert(newValue)
                }

                List {
                    Section {
                        if groupsWithLands.isEmpty {
                            Text(language.localized("No groups with lands yet", "Aún no hay grupos con terrenos"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(groupsWithLands) { group in
                                DisclosureGroup(
                                    isExpanded: expansionBinding(for: group.id)
                                ) {
                                    if sortedLands(for: group).isEmpty {
                                        Text(language.localized("No lands in this group", "No hay parcelas en este grupo"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(sortedLands(for: group)) { land in
                                            Button {
                                                selectedGroupID = group.id
                                                selectedParcelID = land.id
                                            } label: {
                                                ParcelMapRow(
                                                    land: land,
                                                    isSelected: selectedParcelID == land.id
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                } label: {
                                    GroupMapRow(
                                        group: group,
                                        isSelected: selectedGroupID == group.id,
                                        language: language,
                                        onFocusGroup: {
                                            selectedGroupID = group.id
                                            selectedParcelID = nil
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text(language.localized("Groups", "Grupos"))
                    }
                }
                .frame(maxHeight: 260)
            }
            .navigationTitle(language.localized("Land Map", "Mapa"))
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    SettingsToolbarButton {
                        showingSettings = true
                    }
                    AccountToolbarButton {
                        showingAccount = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.localized("Fit All", "Ver todo")) {
                        selectedParcelID = nil
                        selectedGroupID = nil
                        expandedGroupIDs.removeAll()
                        moveCamera(to: regionForLands(lands))
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .sheet(isPresented: $showingAccount) {
                NavigationStack {
                    AccountView()
                }
            }
        }
    }

    private var groupsWithLands: [LandGroup] {
        groups.filter { !$0.lands.isEmpty }
    }

    private var selectedParcel: Land? {
        guard let selectedParcelID else { return nil }
        return lands.first(where: { $0.id == selectedParcelID })
    }

    private var hasSelectedParcel: Bool {
        selectedParcelID != nil
    }

    private func sortedLands(for group: LandGroup) -> [Land] {
        group.lands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func expansionBinding(for groupID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedGroupIDs.contains(groupID) },
            set: { isExpanded in
                if isExpanded {
                    expandedGroupIDs.insert(groupID)
                    if let group = groups.first(where: { $0.id == groupID }) {
                        selectedGroupID = groupID
                        selectedParcelID = nil
                        moveCamera(to: regionForGroup(group))
                    }
                } else {
                    expandedGroupIDs.remove(groupID)
                }
            }
        )
    }

    private func moveCamera(to region: MKCoordinateRegion, animated: Bool = true) {
        if animated {
            withAnimation(.easeInOut(duration: 0.42)) {
                position = .region(region)
            }
        } else {
            position = .region(region)
        }
    }

    private func regionForLands(_ lands: [Land]) -> MKCoordinateRegion {
        guard !lands.isEmpty else {
            return Self.defaultRegion()
        }

        let ringCoords = lands.flatMap { $0.catastroRings }.flatMap { $0 }
        if let region = regionForCoordinates(ringCoords) {
            return region
        }

        let lats = lands.map { $0.latitude }
        let lons = lands.map { $0.longitude }

        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max(0.08, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.08, (maxLon - minLon) * 1.4)
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    private func regionForLand(_ land: Land) -> MKCoordinateRegion {
        if let region = regionForCoordinates(land.catastroRings.flatMap { $0 }) {
            return region
        }
        return MKCoordinateRegion(
            center: land.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    }

    private func regionForGroup(_ group: LandGroup) -> MKCoordinateRegion {
        regionForLands(group.lands)
    }

    private func color(for land: Land) -> Color {
        if let group = land.group {
            return Color(hex: group.colorHex)
        }
        if let item = ProductionCatalog.item(for: land.productionType) {
            return Color(hex: item.colorHex)
        }
        let hash = abs(land.name.hashValue)
        let palette: [Color] = [.green, .blue, .orange, .red, .teal, .pink]
        return palette[hash % palette.count]
    }

    private func fillOpacity(for land: Land) -> Double {
        if selectedParcelID == land.id {
            return 0.33
        }
        if hasSelectedParcel {
            return 0.06
        }
        return 0.18
    }

    private func strokeWidth(for land: Land) -> CGFloat {
        if selectedParcelID == land.id {
            return 3.4
        }
        if hasSelectedParcel {
            return 1.0
        }
        return 1.6
    }

    private func regionForCoordinates(_ coords: [Coordinate]) -> MKCoordinateRegion? {
        guard let first = coords.first else { return nil }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.3),
            longitudeDelta: max(0.02, (maxLon - minLon) * 1.3)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func defaultRegion() -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
        )
    }
}

private struct GroupMapRow: View {
    let group: LandGroup
    let isSelected: Bool
    let language: AppLanguage
    let onFocusGroup: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: group.colorHex))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                Text("\(group.lands.count) \(language.localized("lands", "terrenos"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onFocusGroup) {
                Image(systemName: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private struct ParcelMapRow: View {
    let land: Land
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isSelected ? Color.yellow : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(land.name)
                    .font(.subheadline.weight(.semibold))
                Text(land.locationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "scope")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
