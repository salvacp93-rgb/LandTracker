import SwiftUI
import SwiftData
import MapKit

struct GroupListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismissSearch) private var dismissSearch
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel
    @Query private var lands: [Land]
    @Query(sort: \LandGroup.name) private var groups: [LandGroup]
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @State private var showingAccount = false
    @State private var showingSettings = false
    @State private var showingCreate = false
    @State private var searchText = ""
    @State private var selectedGroupRoute: GroupRoute?
    @State private var selectedMode: GroupHubMode = .list
    @State private var position: MapCameraPosition = .region(Self.defaultRegion())
    @State private var selectedParcelID: UUID?
    @State private var selectedGroupID: UUID?
    @State private var expandedGroupIDs: Set<UUID> = []

    private let accentBlue = Color(red: 0.39, green: 0.49, blue: 0.64)
    private let accentGreen = Color(red: 0.49, green: 0.57, blue: 0.66)

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    viewModeCard

                    if selectedMode == .list {
                        listContent
                    } else {
                        mapContent
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(language.localized("Groups", "Grupos"))
            .navigationDestination(item: $selectedGroupRoute) { route in
                if let group = groups.first(where: { $0.id == route.groupID }) {
                    GroupDetailView(group: group)
                } else {
                    Text(language.localized("Group not found", "Grupo no encontrado"))
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $searchText, prompt: language.localized("Search groups", "Buscar grupos"))
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    SettingsToolbarButton {
                        showingSettings = true
                    }

                    AccountToolbarButton {
                        showingAccount = true
                    }
                }

                if roleAccessViewModel.canManageStructure {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingCreate = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                GroupEditorView()
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
        .onChange(of: selectedMode) { _, newValue in
            guard newValue == .map else { return }
            refreshMapCamera(animated: false)
        }
        .onChange(of: selectedParcelID) { _, _ in
            guard selectedMode == .map else { return }
            if let selectedParcel {
                moveCamera(to: regionForLand(selectedParcel))
            }
        }
        .onChange(of: selectedGroupID) { _, newValue in
            guard selectedMode == .map, let newValue else { return }
            if selectedParcelID != nil {
                expandedGroupIDs.insert(newValue)
                return
            }
            guard let group = groups.first(where: { $0.id == newValue }) else { return }
            moveCamera(to: regionForGroup(group))
            expandedGroupIDs.insert(newValue)
        }
        .onChange(of: lands) { _, _ in
            guard selectedMode == .map else { return }
            refreshMapCamera(animated: selectedGroupID != nil || selectedParcelID != nil)
        }
        .onChange(of: groups) { _, _ in
            guard selectedMode == .map else { return }
            refreshMapCamera(animated: selectedGroupID != nil || selectedParcelID != nil)
        }
    }

    private var viewModeCard: some View {
        Picker(language.localized("View", "Vista"), selection: $selectedMode) {
            ForEach(GroupHubMode.allCases) { mode in
                Text(mode.title(language: language)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(6)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                accentBlue.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.44), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var listContent: some View {
        if filteredGroups.isEmpty {
            GlassPanelCard(
                title: language.localized("No groups yet", "Todavía no hay grupos"),
                subtitle: language.localized("Create your first group to start organizing lands with color, structure and shared context.", "Crea tu primer grupo para empezar a organizar terrenos con color, estructura y contexto compartido."),
                systemImage: "square.grid.2x2",
                tint: accentBlue
            ) {
                if roleAccessViewModel.canManageStructure {
                    Button {
                        showingCreate = true
                    } label: {
                        Label(language.localized("Create group", "Crear grupo"), systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentBlue)
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredGroups) { group in
                    Button {
                        selectedGroupRoute = GroupRoute(groupID: group.id)
                    } label: {
                        GroupSummaryCard(
                            group: group,
                            language: language,
                            canManageStructure: roleAccessViewModel.canManageStructure,
                            onDelete: {
                                deleteGroup(group)
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var mapContent: some View {
        GlassPanelCard(
            title: nil,
            subtitle: nil,
            systemImage: "map.fill",
            tint: accentBlue
        ) {
            if selectedGroup != nil || selectedParcel != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if let selectedGroup {
                            GroupGlassPill(
                                title: language.localized("Group", "Grupo"),
                                value: selectedGroup.name,
                                systemImage: "square.grid.2x2.fill",
                                tint: Color(hex: selectedGroup.colorHex)
                            )
                        }

                        if let selectedParcel {
                            GroupGlassPill(
                                title: language.localized("Land", "Terreno"),
                                value: selectedParcel.name,
                                systemImage: "leaf.fill",
                                tint: selectedParcel.group.map { Color(hex: $0.colorHex) } ?? accentGreen
                            )
                        }
                    }

                    Button {
                        resetMapSelection()
                    } label: {
                        Label(language.localized("Fit All", "Ver todo"), systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.thinMaterial)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(accentBlue.opacity(0.16), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

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
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            )
            .onAppear {
                refreshMapCamera(animated: false)
            }
        }

        GlassPanelCard(
            title: nil,
            subtitle: nil,
            systemImage: "scope",
            tint: accentGreen
        ) {
            if filteredGroupsWithLands.isEmpty {
                Text(language.localized("No groups with lands available for this search.", "No hay grupos con terrenos disponibles para esta búsqueda."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredGroupsWithLands) { group in
                        GroupMapBrowserCard(
                            group: group,
                            lands: visibleLands(for: group),
                            isExpanded: isGroupExpandedInMap(group),
                            isSelected: selectedGroupID == group.id,
                            selectedParcelID: selectedParcelID,
                            language: language,
                            onToggleExpansion: {
                                toggleExpansion(for: group)
                            },
                            onFocusGroup: {
                                dismissSearch()
                                selectedGroupID = group.id
                                selectedParcelID = nil
                                expandedGroupIDs.insert(group.id)
                                moveCamera(to: regionForGroup(group))
                            },
                            onSelectLand: { land in
                                dismissSearch()
                                selectedGroupID = group.id
                                selectedParcelID = land.id
                                expandedGroupIDs.insert(group.id)
                                moveCamera(to: regionForLand(land))
                            },
                            onOpenLand: { land in
                                dismissSearch()
                                selectedGroupID = group.id
                                selectedParcelID = land.id
                                expandedGroupIDs.insert(group.id)
                                moveCamera(to: regionForLand(land))
                            }
                        )
                    }
                }
            }
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredGroups: [LandGroup] {
        guard !trimmedSearchText.isEmpty else { return groups }
        return groups.filter { group in
            groupMatchesSearch(group) || group.lands.contains(where: landMatchesSearch)
        }
    }

    private var filteredGroupsWithLands: [LandGroup] {
        filteredGroups.filter { !$0.lands.isEmpty }
    }

    private var selectedParcel: Land? {
        guard let selectedParcelID else { return nil }
        return lands.first(where: { $0.id == selectedParcelID })
    }

    private var selectedGroup: LandGroup? {
        guard let selectedGroupID else { return nil }
        return groups.first(where: { $0.id == selectedGroupID })
    }

    private var hasSelectedParcel: Bool {
        selectedParcelID != nil
    }

    private func sortedLands(for group: LandGroup) -> [Land] {
        group.lands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func visibleLands(for group: LandGroup) -> [Land] {
        let matches = sortedLands(for: group).filter(landMatchesSearch)
        guard !trimmedSearchText.isEmpty, !matches.isEmpty else {
            return sortedLands(for: group)
        }
        return matches
    }

    private func isGroupExpandedInMap(_ group: LandGroup) -> Bool {
        expandedGroupIDs.contains(group.id) || shouldAutoExpandGroupInMap(group)
    }

    private func shouldAutoExpandGroupInMap(_ group: LandGroup) -> Bool {
        !trimmedSearchText.isEmpty && !sortedLands(for: group).filter(landMatchesSearch).isEmpty
    }

    private func groupMatchesSearch(_ group: LandGroup) -> Bool {
        group.name.localizedCaseInsensitiveContains(trimmedSearchText)
    }

    private func landMatchesSearch(_ land: Land) -> Bool {
        guard !trimmedSearchText.isEmpty else { return true }

        let localizedActivity = ActivityCatalog.displayName(for: land.activityType, language: language)
        let localizedProduction = ProductionCatalog.displayName(for: land.productionType, language: language)
        let localizedSubtype = ProductionCatalog.displayVarietyName(for: land.productionSubtype, language: language)

        return land.name.localizedCaseInsensitiveContains(trimmedSearchText) ||
            land.activityType.localizedCaseInsensitiveContains(trimmedSearchText) ||
            localizedActivity.localizedCaseInsensitiveContains(trimmedSearchText) ||
            land.productionType.localizedCaseInsensitiveContains(trimmedSearchText) ||
            localizedProduction.localizedCaseInsensitiveContains(trimmedSearchText) ||
            land.productionSubtype.localizedCaseInsensitiveContains(trimmedSearchText) ||
            localizedSubtype.localizedCaseInsensitiveContains(trimmedSearchText)
    }

    private func deleteGroup(_ group: LandGroup) {
        guard roleAccessViewModel.canManageStructure else { return }
        let id = group.id
        context.delete(group)
        try? context.save()
        Task { @MainActor in
            await SupabaseSyncService.shared.queueGroupDelete(id: id, context: context)
        }
    }

    private func toggleExpansion(for group: LandGroup) {
        if expandedGroupIDs.contains(group.id) {
            expandedGroupIDs.remove(group.id)
        } else {
            expandedGroupIDs.insert(group.id)
            selectedGroupID = group.id
            selectedParcelID = nil
            moveCamera(to: regionForGroup(group))
        }
    }

    private func resetMapSelection() {
        selectedParcelID = nil
        selectedGroupID = nil
        expandedGroupIDs.removeAll()
        moveCamera(to: regionForLands(lands))
    }

    private func refreshMapCamera(animated: Bool) {
        if let selectedParcel {
            moveCamera(to: regionForLand(selectedParcel), animated: animated)
        } else if let selectedGroupID,
                  let group = groups.first(where: { $0.id == selectedGroupID }),
                  !group.lands.isEmpty {
            moveCamera(to: regionForGroup(group), animated: animated)
        } else {
            moveCamera(to: regionForLands(lands), animated: animated)
        }
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
        if let region = regionForCoordinates(
            land.catastroRings.flatMap { $0 },
            minimumDelta: 0.004,
            paddingMultiplier: 1.15
        ) {
            return region
        }
        return MKCoordinateRegion(
            center: land.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
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

    private func regionForCoordinates(
        _ coords: [Coordinate],
        minimumDelta: Double = 0.02,
        paddingMultiplier: Double = 1.3
    ) -> MKCoordinateRegion? {
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

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(minimumDelta, (maxLat - minLat) * paddingMultiplier),
            longitudeDelta: max(minimumDelta, (maxLon - minLon) * paddingMultiplier)
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

private enum GroupHubMode: String, CaseIterable, Identifiable {
    case list
    case map

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .list:
            return language.localized("List", "Lista")
        case .map:
            return language.localized("Map", "Mapa")
        }
    }
}

private struct GroupRoute: Hashable, Identifiable {
    let groupID: UUID
    var id: UUID { groupID }
}

private struct GroupSummaryCard: View {
    let group: LandGroup
    let language: AppLanguage
    let canManageStructure: Bool
    let onDelete: () -> Void

    private var groupColor: Color {
        Color(hex: group.colorHex)
    }

    private var landsCountText: String {
        let count = group.lands.count
        let unit = count == 1
            ? language.localized("land", "terreno")
            : language.localized("lands", "terrenos")
        return "\(count) \(unit)"
    }

    var body: some View {
        TintedGlassCard(tint: groupColor) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
                    .frame(width: 54, height: 54)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.26),
                                        groupColor.opacity(0.22)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(groupColor.opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(groupColor.opacity(0.18), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 10) {
                    Text(group.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    GroupCountBadge(
                        text: landsCountText,
                        tint: groupColor
                    )
                }

                Spacer(minLength: 0)
            }
        }
        .contextMenu {
            if canManageStructure {
                Button(role: .destructive, action: onDelete) {
                    Label(language.localized("Delete group", "Eliminar grupo"), systemImage: "trash")
                }
            }
        }
    }
}

private struct GroupMapBrowserCard: View {
    let group: LandGroup
    let lands: [Land]
    let isExpanded: Bool
    let isSelected: Bool
    let selectedParcelID: UUID?
    let language: AppLanguage
    let onToggleExpansion: () -> Void
    let onFocusGroup: () -> Void
    let onSelectLand: (Land) -> Void
    let onOpenLand: (Land) -> Void

    private var groupColor: Color {
        Color(hex: group.colorHex)
    }

    private var landsCountText: String {
        let count = group.lands.count
        let unit = count == 1
            ? language.localized("land", "terreno")
            : language.localized("lands", "terrenos")
        return "\(count) \(unit)"
    }

    var body: some View {
        TintedGlassCard(tint: groupColor, isHighlighted: isSelected || isExpanded, cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.24),
                                            groupColor.opacity(0.18)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(groupColor.opacity(0.9))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(groupColor.opacity(0.18), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        GroupCountBadge(
                            text: landsCountText,
                            tint: groupColor
                        )
                    }

                    Spacer(minLength: 0)

                    Button(action: onFocusGroup) {
                        Image(systemName: "scope")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? groupColor : .secondary)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(.thinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(isSelected ? 0.2 : 0.08),
                                                groupColor.opacity(isSelected ? 0.2 : 0.08)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                    .buttonStyle(.plain)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(groupColor.opacity(0.74))
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleExpansion)

                if isExpanded {
                    VStack(spacing: 8) {
                        ForEach(lands) { land in
                            ParcelBrowserRow(
                                land: land,
                                isSelected: selectedParcelID == land.id,
                                tint: groupColor,
                                dotColor: groupColor,
                                detailsLabel: language.localized("Open details", "Abrir detalles"),
                                onFocus: {
                                    onSelectLand(land)
                                },
                                onOpenDetails: {
                                    onOpenLand(land)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct GroupCountBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
        .foregroundStyle(tint.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct ParcelBrowserRow: View {
    let land: Land
    let isSelected: Bool
    let tint: Color
    let dotColor: Color
    let detailsLabel: String
    let onFocus: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onFocus) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(isSelected ? dotColor : dotColor.opacity(0.28))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(land.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)

                        Text(land.locationText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink {
                LandDetailView(land: land)
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(tint.opacity(0.18), lineWidth: 1)
                            .allowsHitTesting(false)
                    )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded(onOpenDetails))
            .accessibilityLabel(detailsLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isSelected ? 0.18 : 0.1),
                            tint.opacity(isSelected ? 0.12 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(isSelected ? 0.24 : 0.12), lineWidth: 1)
                .allowsHitTesting(false)
        )
    }
}

private struct GroupGlassPill: View {
    let title: String
    let value: String
    let systemImage: String
    let iconText: String?
    let tint: Color

    init(
        title: String,
        value: String,
        systemImage: String,
        iconText: String? = nil,
        tint: Color
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.iconText = iconText
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let iconText, !iconText.isEmpty {
                    Text(iconText)
                        .font(.caption)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint.opacity(0.9))
                        .frame(width: 24, height: 24)
                }
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    tint.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            tint.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            tint.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

private struct TintedGlassCard<Content: View>: View {
    let tint: Color
    let isHighlighted: Bool
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: Content

    init(
        tint: Color,
        isHighlighted: Bool = false,
        cornerRadius: CGFloat = 24,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.isHighlighted = isHighlighted
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHighlighted ? 0.26 : 0.18),
                                    tint.opacity(isHighlighted ? 0.16 : 0.1),
                                    tint.opacity(isHighlighted ? 0.08 : 0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(isHighlighted ? 0.05 : 0.025))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHighlighted ? 0.42 : 0.28),
                                tint.opacity(isHighlighted ? 0.18 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: tint.opacity(isHighlighted ? 0.12 : 0.06), radius: 10, x: 0, y: 6)
    }
}

struct GroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue

    @State private var name: String = ""
    @State private var colorHex: String = GroupColorPalette.hexValues.first ?? "2D9CDB"

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var selectedColor: Color {
        Color(hex: colorHex)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassPanelCard(
                        title: language.localized("Group name", "Nombre del grupo"),
                        subtitle: language.localized("Use a short, easy-to-recognize name to organize your lands.", "Escribe un nombre corto y fácil de reconocer para organizar tus terrenos."),
                        systemImage: "character.textbox",
                        tint: selectedColor
                    ) {
                        groupEditorFieldShell(
                            label: language.localized("Name", "Nombre"),
                            systemImage: "textformat",
                            tint: selectedColor
                        ) {
                            TextField(
                                language.localized("Example: North fields", "Ejemplo: Campos norte"),
                                text: $name
                            )
                            .textInputAutocapitalization(.words)
                        }
                    }

                    GlassPanelCard(
                        title: language.localized("Color", "Color"),
                        subtitle: language.localized("Select the color that will identify this group across the app and on the map.", "Selecciona el color que identificará al grupo en la app y en el mapa."),
                        systemImage: "paintpalette.fill",
                        tint: selectedColor
                    ) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 12)], spacing: 12) {
                            ForEach(GroupColorPalette.hexValues, id: \.self) { hex in
                                GroupColorChoiceCard(
                                    color: Color(hex: hex),
                                    isSelected: colorHex == hex,
                                    selectedLabel: language.localized("Selected", "Seleccionado")
                                ) {
                                    colorHex = hex
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selectedColor)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selectedColor.opacity(0.18), lineWidth: 1)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.localized("Current color", "Color actual"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text("#" + colorHex)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(language.localized("New Group", "Nuevo grupo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(language.localized("Cancel", "Cancelar")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.localized("Save", "Guardar")) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private func groupEditorFieldShell<Content: View>(
        label: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 1)
                )
        }
    }

    private func save() {
        let group = LandGroup(name: trimmedName, colorHex: colorHex)
        context.insert(group)
        try? context.save()
        Task { @MainActor in
            await SupabaseSyncService.shared.queueGroupUpsert(id: group.id, context: context)
        }
        dismiss()
    }
}

private struct GroupColorChoiceCard: View {
    let color: Color
    let isSelected: Bool
    let selectedLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.78), lineWidth: 1.5)
                    )

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? color : .secondary)

                Text(isSelected ? selectedLabel : " ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSelected ? 0.24 : 0.1),
                                color.opacity(isSelected ? 0.2 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? color.opacity(0.34) : Color.white.opacity(0.18),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    UserDefaults.standard.set(AppAccessRole.owner.rawValue, forKey: "access.activeRole")

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Land.self, LandHistoryEntry.self, LandGroup.self, LandTask.self, PendingSyncOperation.self,
        configurations: config
    )

    let ctx = container.mainContext
    let group = LandGroup(name: "Cortijo San Marcos", colorHex: "#059669")
    ctx.insert(group)
    let land = Land(
        name: "Cuartel Alto",
        latitude: 38.019, longitude: -3.371,
        sizeAcres: 29.6,
        productionType: ProductionCatalog.oliveGrove,
        productionSubtype: "Picual",
        incomeAnnual: 14500,
        notes: ""
    )
    land.group = group
    ctx.insert(land)

    return GroupListView()
        .modelContainer(container)
        .environmentObject(RoleAccessViewModel())
}
