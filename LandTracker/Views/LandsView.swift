import SwiftUI
import SwiftData
import MapKit
import UniformTypeIdentifiers

/// The single "Lands" tab. It replaces the former Groups and Lands tabs: one search field,
/// one list where groups are pinned section headers and lands are directly tappable rows,
/// and a map mode that browses the same sections (plus "Ungrouped").
struct LandsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismissSearch) private var dismissSearch
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel
    @Query(sort: \Land.name) private var lands: [Land]
    @Query(sort: \LandGroup.name) private var groups: [LandGroup]
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @AppStorage(AccountPreferences.measurementSystemKey) private var measurementSystemRaw = AppSettings.defaultMeasurementSystem.rawValue
    @State private var showingAccount = false
    @State private var showingSettings = false
    @State private var showingCreateLand = false
    @State private var showingCreateGroup = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportData: Data?
    @State private var ioError: String?
    @State private var searchText = ""
    @State private var selectedGroupRoute: GroupRoute?
    @State private var groupPendingDeletion: LandGroup?
    @State private var landPendingDeletion: PendingLandDeletion?
    @State private var selectedMode: LandsHubMode = .list
    @State private var position: MapCameraPosition = .region(Self.defaultRegion())
    @State private var selectedParcelID: UUID?
    @State private var selectedSectionID: String?
    @State private var expandedSectionIDs: Set<String> = []

    private let accentBlue = Color(red: 0.39, green: 0.49, blue: 0.64)
    private let accentGreen = Color(red: 0.49, green: 0.57, blue: 0.66)
    private let neutralTint = Color(red: 0.55, green: 0.60, blue: 0.68)

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var measurementSystem: AppMeasurementSystem {
        AppSettings.measurementSystem(from: measurementSystemRaw)
    }

    var body: some View {
        let sections = LandsHubViewModel.sections(
            lands: lands,
            groups: groups,
            searchText: searchText,
            language: language
        )

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if lands.isEmpty && groups.isEmpty {
                        noLandsCard
                    } else {
                        viewModeCard

                        if selectedMode == .list {
                            listContent(sections)
                        } else {
                            mapContent(sections)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(language.localized("Lands", "Terrenos"))
            .searchable(
                text: $searchText,
                prompt: language.localized("Search lands or groups", "Buscar terrenos o grupos")
            )
            .navigationDestination(for: Land.self) { land in
                LandDetailView(land: land)
            }
            .navigationDestination(item: $selectedGroupRoute) { route in
                if let group = groups.first(where: { $0.id == route.groupID }) {
                    GroupDetailView(group: group)
                } else {
                    Text(language.localized("Group not found", "Grupo no encontrado"))
                        .foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    SettingsToolbarButton(language: language) {
                        showingSettings = true
                    }

                    AccountToolbarButton(language: language) {
                        showingAccount = true
                    }

                    if roleAccessViewModel.canManageStructure {
                        Menu {
                            Button(language.localized("Export JSON", "Exportar JSON")) {
                                do {
                                    exportData = try ImportExportService.exportData(lands: lands, groups: groups)
                                    showingExporter = true
                                } catch {
                                    ioError = error.localizedDescription
                                }
                            }
                            Button(language.localized("Import JSON", "Importar JSON")) {
                                showingImporter = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel(language.localized("More options", "Más opciones"))
                    }
                }

                if roleAccessViewModel.canManageStructure {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showingCreateLand = true
                            } label: {
                                Label(language.localized("New land", "Nuevo terreno"), systemImage: "leaf")
                            }

                            Button {
                                showingCreateGroup = true
                            } label: {
                                Label(language.localized("New group", "Nuevo grupo"), systemImage: "square.grid.2x2")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(language.localized("Add", "Añadir"))
                    }
                }
            }
            .sheet(isPresented: $showingAccount) {
                NavigationStack {
                    AccountView()
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .sheet(isPresented: $showingCreateLand) {
                LandEditorView(mode: .create)
            }
            .sheet(isPresented: $showingCreateGroup) {
                GroupEditorView()
            }
            .confirmationDialog(
                groupDeletionTitle,
                isPresented: isConfirmingGroupDeletion,
                titleVisibility: .visible,
                presenting: groupPendingDeletion
            ) { group in
                Button(language.localized("Delete group", "Eliminar grupo"), role: .destructive) {
                    deleteGroup(group)
                }
            } message: { _ in
                Text(language.localized(
                    "The lands in this group are not deleted. They will move to Ungrouped.",
                    "Los terrenos de este grupo no se eliminan. Pasarán a «Sin grupo»."
                ))
            }
            .confirmationDialog(
                landDeletionTitle,
                isPresented: isConfirmingLandDeletion,
                titleVisibility: .visible,
                presenting: landPendingDeletion
            ) { pending in
                Button(language.localized("Delete land", "Eliminar terreno"), role: .destructive) {
                    confirmLandDeletion(pending)
                }
            } message: { _ in
                Text(language.localized(
                    "Its history, tasks and costs will be deleted. This can't be undone.",
                    "Se eliminarán su historial, tareas y costes. No se puede deshacer."
                ))
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: ExportDocument(data: exportData ?? Data()),
                contentType: .json,
                defaultFilename: "LandTracker-Export"
            ) { result in
                if case .failure(let error) = result {
                    ioError = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                do {
                    let url = try result.get()
                    let data = try Data(contentsOf: url)
                    try ImportExportService.importData(data, context: context)
                    try? context.save()
                    Task { @MainActor in
                        let importedTasks = (try? context.fetch(FetchDescriptor<LandTask>())) ?? []
                        await TaskReminderService.shared.syncReminders(for: importedTasks, language: language)
                        await SupabaseSyncService.shared.queueAllLocalDataForSync(context: context)
                    }
                } catch {
                    ioError = error.localizedDescription
                }
            }
            .alert(
                language.localized("Import/Export Error", "Error de importación o exportación"),
                isPresented: Binding(get: { ioError != nil }, set: { _ in ioError = nil })
            ) {
                Button(language.localized("OK", "Aceptar"), role: .cancel) {}
            } message: {
                Text(ioError ?? "")
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
        .onChange(of: selectedSectionID) { _, newValue in
            guard selectedMode == .map, let newValue else { return }
            if selectedParcelID != nil {
                expandedSectionIDs.insert(newValue)
                return
            }
            moveCamera(to: regionForSection(id: newValue))
            expandedSectionIDs.insert(newValue)
        }
        .onChange(of: lands) { _, _ in
            pruneStaleSelection()
            guard selectedMode == .map else { return }
            refreshMapCamera(animated: selectedSectionID != nil || selectedParcelID != nil)
        }
        .onChange(of: groups) { _, _ in
            pruneStaleSelection()
            guard selectedMode == .map else { return }
            refreshMapCamera(animated: selectedSectionID != nil || selectedParcelID != nil)
        }
    }

    // MARK: - Shared chrome

    private var viewModeCard: some View {
        Picker(language.localized("View", "Vista"), selection: $selectedMode) {
            ForEach(LandsHubMode.allCases) { mode in
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

    private var noLandsCard: some View {
        GlassPanelCard(
            title: language.localized("No lands yet", "Todavía no hay terrenos"),
            subtitle: language.localized(
                "Create your first land to start working with maps, devices and grouped structure.",
                "Crea tu primer terreno para empezar a trabajar con mapas, dispositivos y estructura agrupada."
            ),
            systemImage: "leaf.circle.fill",
            tint: neutralTint
        ) {
            if roleAccessViewModel.canManageStructure {
                Button {
                    showingCreateLand = true
                } label: {
                    Label(language.localized("Create land", "Crear terreno"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(neutralTint)
            }
        }
    }

    private var noMatchingLandsCard: some View {
        GlassPanelCard(
            title: language.localized("No matching lands", "No hay terrenos que coincidan"),
            subtitle: language.localized(
                "Try another search term or clear the filter to see all your lands again.",
                "Prueba otro término o limpia la búsqueda para volver a ver todos tus terrenos."
            ),
            systemImage: "leaf.circle.fill",
            tint: neutralTint
        ) {
            EmptyView()
        }
    }

    // MARK: - List mode

    @ViewBuilder
    private func listContent(_ sections: [LandsHubViewModel.Section]) -> some View {
        if sections.isEmpty {
            noMatchingLandsCard
        } else if groups.isEmpty {
            // No groups at all: a flat list with no header keeps it simple; owners still get a
            // hint so creating the first group stays discoverable.
            LazyVStack(spacing: 10) {
                ForEach(sections.flatMap(\.lands)) { land in
                    landRow(land, tint: neutralTint)
                }

                if roleAccessViewModel.canManageStructure && trimmedSearchText.isEmpty {
                    newGroupHintCard
                        .padding(.top, 6)
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        if section.lands.isEmpty {
                            emptyGroupRow
                        } else {
                            ForEach(section.lands) { land in
                                landRow(land, tint: tint(for: section))
                            }
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ section: LandsHubViewModel.Section) -> some View {
        let countText = language.landsCountText(section.lands.count)

        Group {
            if let group = section.group {
                Button {
                    selectedGroupRoute = GroupRoute(groupID: group.id)
                } label: {
                    LandsSectionHeaderContent(
                        title: group.name,
                        countText: countText,
                        tint: Color(hex: group.colorHex),
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if roleAccessViewModel.canManageStructure {
                        Button(role: .destructive) {
                            groupPendingDeletion = group
                        } label: {
                            Label(language.localized("Delete group", "Eliminar grupo"), systemImage: "trash")
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(group.name), \(countText)")
                .accessibilityHint(language.localized("Opens the group details", "Abre los detalles del grupo"))
                .accessibilityAddTraits([.isButton, .isHeader])
                .accessibilityActions {
                    if roleAccessViewModel.canManageStructure {
                        Button(language.localized("Delete group", "Eliminar grupo")) {
                            groupPendingDeletion = group
                        }
                    }
                }
            } else {
                LandsSectionHeaderContent(
                    title: language.localized("Ungrouped", "Sin grupo"),
                    countText: countText,
                    tint: neutralTint,
                    showsChevron: false
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(language.localized("Ungrouped", "Sin grupo")), \(countText)")
                .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
    }

    private func landRow(_ land: Land, tint: Color) -> some View {
        NavigationLink(value: land) {
            LandRowCard(
                land: land,
                dotColor: land.group.map { Color(hex: $0.colorHex) } ?? tint,
                language: language,
                measurementSystem: measurementSystem,
                canManageStructure: roleAccessViewModel.canManageStructure,
                onDelete: {
                    landPendingDeletion = PendingLandDeletion(id: land.id, name: land.name)
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyGroupRow: some View {
        Text(language.localized("No lands in this group yet", "Este grupo aún no tiene terrenos"))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private var newGroupHintCard: some View {
        GlassPanelCard(
            title: language.localized("Organize your lands into groups", "Organiza tus terrenos en grupos"),
            subtitle: language.localized(
                "A group brings several lands together with a color and shared totals.",
                "Un grupo reúne varios terrenos con un color y totales compartidos."
            ),
            systemImage: "square.grid.2x2",
            tint: accentBlue
        ) {
            Button {
                showingCreateGroup = true
            } label: {
                Label(language.localized("New group", "Nuevo grupo"), systemImage: "plus.circle.fill")
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(accentBlue)
        }
    }

    private func tint(for section: LandsHubViewModel.Section) -> Color {
        section.group.map { Color(hex: $0.colorHex) } ?? neutralTint
    }

    // MARK: - Map mode

    @ViewBuilder
    private func mapContent(_ sections: [LandsHubViewModel.Section]) -> some View {
        let browsableSections = sections.filter { !$0.lands.isEmpty }

        GlassPanelCard(
            title: nil,
            subtitle: nil,
            systemImage: "map.fill",
            tint: accentBlue
        ) {
            if selectedSectionSummary != nil || selectedParcel != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if let selectedSectionSummary {
                            GlassPill(
                                title: language.localized("Group", "Grupo"),
                                value: selectedSectionSummary.title,
                                systemImage: "square.grid.2x2.fill",
                                tint: selectedSectionSummary.tint
                            )
                        }

                        if let selectedParcel {
                            GlassPill(
                                title: language.localized("Land", "Terreno"),
                                value: selectedParcel.name,
                                systemImage: "leaf.fill",
                                tint: selectedParcel.group.map { Color(hex: $0.colorHex) } ?? neutralTint
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
                            .frame(minHeight: 44)
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
            if browsableSections.isEmpty {
                Text(language.localized(
                    "No lands available for this search.",
                    "No hay terrenos disponibles para esta búsqueda."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(browsableSections) { section in
                        LandsMapBrowserCard(
                            title: section.group?.name ?? language.localized("Ungrouped", "Sin grupo"),
                            systemImage: section.isUngrouped ? "tray.fill" : "square.grid.2x2.fill",
                            tint: tint(for: section),
                            count: section.lands.count,
                            lands: section.lands,
                            isExpanded: isSectionExpandedInMap(section),
                            isSelected: selectedSectionID == section.id,
                            selectedParcelID: selectedParcelID,
                            language: language,
                            onToggleExpansion: {
                                toggleExpansion(for: section)
                            },
                            onFocusSection: {
                                dismissSearch()
                                selectedSectionID = section.id
                                selectedParcelID = nil
                                expandedSectionIDs.insert(section.id)
                                moveCamera(to: regionForSection(id: section.id))
                            },
                            onSelectLand: { land in
                                dismissSearch()
                                selectedSectionID = section.id
                                selectedParcelID = land.id
                                expandedSectionIDs.insert(section.id)
                                moveCamera(to: regionForLand(land))
                            },
                            onOpenLand: { land in
                                dismissSearch()
                                selectedSectionID = section.id
                                selectedParcelID = land.id
                                expandedSectionIDs.insert(section.id)
                                moveCamera(to: regionForLand(land))
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - State helpers

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedParcel: Land? {
        guard let selectedParcelID else { return nil }
        return lands.first(where: { $0.id == selectedParcelID })
    }

    private var selectedSectionSummary: (title: String, tint: Color)? {
        guard let selectedSectionID else { return nil }
        if selectedSectionID == LandsHubViewModel.ungroupedSectionID {
            return (language.localized("Ungrouped", "Sin grupo"), neutralTint)
        }
        guard let group = groups.first(where: { $0.id.uuidString == selectedSectionID }) else { return nil }
        return (group.name, Color(hex: group.colorHex))
    }

    /// Based on the resolved land, not the raw id: a stale id (the land was deleted from its
    /// detail screen or by a sync) must not leave every polygon dimmed.
    private var hasSelectedParcel: Bool {
        selectedParcel != nil
    }

    /// Drops selection state that points at lands or sections that no longer exist.
    private func pruneStaleSelection() {
        if let id = selectedParcelID, !lands.contains(where: { $0.id == id }) {
            selectedParcelID = nil
        }

        let hasUngroupedLands = lands.contains {
            LandsHubViewModel.sectionID(for: $0) == LandsHubViewModel.ungroupedSectionID
        }
        let groupIDs = Set(groups.map { $0.id.uuidString })
        func isLive(_ sectionID: String) -> Bool {
            sectionID == LandsHubViewModel.ungroupedSectionID
                ? hasUngroupedLands
                : groupIDs.contains(sectionID)
        }

        if let id = selectedSectionID, !isLive(id) {
            selectedSectionID = nil
        }
        let staleExpanded = expandedSectionIDs.filter { !isLive($0) }
        if !staleExpanded.isEmpty {
            expandedSectionIDs.subtract(staleExpanded)
        }
    }

    private func isSectionExpandedInMap(_ section: LandsHubViewModel.Section) -> Bool {
        expandedSectionIDs.contains(section.id) || !trimmedSearchText.isEmpty
    }

    private func landsInSection(id: String) -> [Land] {
        lands.filter { LandsHubViewModel.sectionID(for: $0) == id }
    }

    private var isConfirmingGroupDeletion: Binding<Bool> {
        Binding(
            get: { groupPendingDeletion != nil },
            set: { isPresented in
                if !isPresented { groupPendingDeletion = nil }
            }
        )
    }

    private var groupDeletionTitle: String {
        guard let name = groupPendingDeletion?.name else { return "" }
        return language.localized("Delete \"\(name)\"?", "¿Eliminar «\(name)»?")
    }

    private var isConfirmingLandDeletion: Binding<Bool> {
        Binding(
            get: { landPendingDeletion != nil },
            set: { isPresented in
                if !isPresented { landPendingDeletion = nil }
            }
        )
    }

    private var landDeletionTitle: String {
        guard let name = landPendingDeletion?.name else { return "" }
        return language.localized("Delete \"\(name)\"?", "¿Eliminar «\(name)»?")
    }

    // MARK: - Mutations

    private func deleteGroup(_ group: LandGroup) {
        guard roleAccessViewModel.canManageStructure else { return }
        let id = group.id
        if selectedSectionID == id.uuidString {
            resetMapSelection()
        }
        // LandGroup.lands uses SwiftData's default nullify rule: the lands survive as Ungrouped.
        context.delete(group)
        try? context.save()
        Task { @MainActor in
            await SupabaseSyncService.shared.queueGroupDelete(id: id, context: context)
        }
    }

    /// Resolves the pending id back to a live land (it may have vanished while the dialog was
    /// open, e.g. via sync) before deleting.
    private func confirmLandDeletion(_ pending: PendingLandDeletion) {
        guard let land = lands.first(where: { $0.id == pending.id }) else { return }
        deleteLand(land)
    }

    private func deleteLand(_ land: Land) {
        guard roleAccessViewModel.canManageStructure else { return }
        let id = land.id
        if selectedParcelID == id {
            selectedParcelID = nil
        }
        context.delete(land)
        try? context.save()
        Task { @MainActor in
            await SupabaseSyncService.shared.queueLandDelete(id: id, context: context)
        }
    }

    // MARK: - Map camera

    private func toggleExpansion(for section: LandsHubViewModel.Section) {
        if expandedSectionIDs.contains(section.id) {
            expandedSectionIDs.remove(section.id)
        } else {
            expandedSectionIDs.insert(section.id)
            selectedSectionID = section.id
            selectedParcelID = nil
            moveCamera(to: regionForSection(id: section.id))
        }
    }

    private func resetMapSelection() {
        selectedParcelID = nil
        selectedSectionID = nil
        expandedSectionIDs.removeAll()
        moveCamera(to: regionForLands(lands))
    }

    private func refreshMapCamera(animated: Bool) {
        if let selectedParcel {
            moveCamera(to: regionForLand(selectedParcel), animated: animated)
        } else if let selectedSectionID, !landsInSection(id: selectedSectionID).isEmpty {
            moveCamera(to: regionForSection(id: selectedSectionID), animated: animated)
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

    private func regionForSection(id: String) -> MKCoordinateRegion {
        regionForLands(landsInSection(id: id))
    }

    private func color(for land: Land) -> Color {
        if let group = land.group {
            return Color(hex: group.colorHex)
        }
        return neutralTint
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

// MARK: - Supporting types

private enum LandsHubMode: String, CaseIterable, Identifiable {
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

/// Snapshot of the land awaiting delete confirmation. Holds plain values, not the `@Model`,
/// so the dialog never touches a land that was removed underneath it.
private struct PendingLandDeletion: Identifiable {
    let id: UUID
    let name: String
}

private extension AppLanguage {
    /// "1 land" / "3 lands" (Spanish: "1 terreno" / "3 terrenos").
    func landsCountText(_ count: Int) -> String {
        let unit = count == 1
            ? localized("land", "terreno")
            : localized("lands", "terrenos")
        return "\(count) \(unit)"
    }
}

// MARK: - List pieces

private struct LandsSectionHeaderContent: View {
    let title: String
    let countText: String
    let tint: Color
    let showsChevron: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(countText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            } else {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Text(countText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct LandRowCard: View {
    let land: Land
    let dotColor: Color
    let language: AppLanguage
    let measurementSystem: AppMeasurementSystem
    let canManageStructure: Bool
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtitle: String {
        let production = land.productionType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !production.isEmpty else { return land.locationText }

        var text = ProductionCatalog.displayName(for: land.productionType, language: language)
        let variety = land.productionSubtype.trimmingCharacters(in: .whitespacesAndNewlines)
        if !variety.isEmpty {
            text += " · " + ProductionCatalog.displayVarietyName(for: land.productionSubtype, language: language)
        }
        return text
    }

    private var areaText: String? {
        guard land.sizeAcres > 0 else { return nil }
        let value = AppSettings.areaValue(fromAcres: land.sizeAcres, system: measurementSystem)
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(AppSettings.areaShortUnit(system: measurementSystem))"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    titleBlock

                    if let areaText {
                        areaLabel(areaText)
                    }
                }

                Spacer(minLength: 0)
            } else {
                titleBlock

                Spacer(minLength: 8)

                if let areaText {
                    areaLabel(areaText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            if canManageStructure {
                Button(role: .destructive, action: onDelete) {
                    Label(language.localized("Delete land", "Eliminar terreno"), systemImage: "trash")
                }
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(land.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private func areaLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Map browser pieces

private struct LandsMapBrowserCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let count: Int
    let lands: [Land]
    let isExpanded: Bool
    let isSelected: Bool
    let selectedParcelID: UUID?
    let language: AppLanguage
    let onToggleExpansion: () -> Void
    let onFocusSection: () -> Void
    let onSelectLand: (Land) -> Void
    let onOpenLand: (Land) -> Void

    var body: some View {
        TintedGlassCard(tint: tint, isHighlighted: isSelected || isExpanded, cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: onToggleExpansion) {
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
                                                    tint.opacity(0.18)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                                .overlay(
                                    Image(systemName: systemImage)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(tint.opacity(0.9))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(tint.opacity(0.18), lineWidth: 1)
                                )
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)

                                CountBadge(
                                    text: language.landsCountText(count),
                                    tint: tint
                                )
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isExpanded
                        ? language.localized("Expanded", "Expandido")
                        : language.localized("Collapsed", "Contraído"))

                    Button(action: onFocusSection) {
                        Image(systemName: "scope")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? tint : .secondary)
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
                                                tint.opacity(isSelected ? 0.2 : 0.08)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.localized("Focus on map", "Centrar en el mapa"))

                    Button(action: onToggleExpansion) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint.opacity(0.74))
                            .frame(minWidth: 32, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                }

                if isExpanded {
                    VStack(spacing: 8) {
                        ForEach(lands) { land in
                            ParcelBrowserRow(
                                land: land,
                                isSelected: selectedParcelID == land.id,
                                tint: tint,
                                dotColor: tint,
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

private struct CountBadge: View {
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
                        .accessibilityHidden(true)

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
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded(onOpenDetails))
            .accessibilityLabel(detailsLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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

private struct GlassPill: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 24, height: 24)
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
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
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

// MARK: - JSON export

private struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
    ctx.insert(LandGroup(name: "Vega baja", colorHex: "#2D9CDB"))

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

    let loose = Land(
        name: "Huerto del Camino",
        latitude: 38.05, longitude: -3.40,
        sizeAcres: 4.2,
        productionType: "",
        productionSubtype: "",
        incomeAnnual: 0,
        notes: ""
    )
    ctx.insert(loose)

    return LandsView()
        .modelContainer(container)
        .environmentObject(RoleAccessViewModel())
}
