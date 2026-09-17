import SwiftUI
import SwiftData

struct LandEditorView: View {
    enum Mode {
        case create
        case edit(Land)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue

    private let mode: Mode

    @State private var name: String
    @State private var activityType: String
    @State private var productionType: String
    @State private var productionSubtype: String
    @State private var customSubtype: String
    @State private var sizeAcres: Double
    @State private var incomeAnnual: Double
    @State private var annualIrrigationCost: Double
    @State private var annualFertilizerCost: Double
    @State private var annualLaborCost: Double
    @State private var annualMaintenanceCost: Double
    @State private var latitude: Double
    @State private var longitude: Double
    @State private var notes: String
    @State private var installedCapacityKW: Double
    @State private var annualElectricityProductionKWh: Double
    @State private var selfConsumptionRate: Double
    @State private var gridExportRate: Double
    @State private var catastroRefcat14: String
    @State private var catastroAreaValue: Double?
    @State private var catastroAreaUom: String?
    @State private var catastroLabel: String?
    @State private var catastroRings: [[Coordinate]]
    @State private var isFetchingCatastro = false
    @State private var catastroError: String?
    @State private var selectedGroup: LandGroup?
    @State private var showingNewGroup = false
    @State private var showingGroupPicker = false

    @Query(sort: \LandGroup.name) private var groups: [LandGroup]

    init(mode: Mode) {
        self.mode = mode

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _activityType = State(initialValue: "")
            _productionType = State(initialValue: "")
            _productionSubtype = State(initialValue: "")
            _customSubtype = State(initialValue: "")
            _sizeAcres = State(initialValue: 0)
            _incomeAnnual = State(initialValue: 0)
            _annualIrrigationCost = State(initialValue: 0)
            _annualFertilizerCost = State(initialValue: 0)
            _annualLaborCost = State(initialValue: 0)
            _annualMaintenanceCost = State(initialValue: 0)
            _latitude = State(initialValue: 0)
            _longitude = State(initialValue: 0)
            _notes = State(initialValue: "")
            _installedCapacityKW = State(initialValue: 0)
            _annualElectricityProductionKWh = State(initialValue: 0)
            _selfConsumptionRate = State(initialValue: 0)
            _gridExportRate = State(initialValue: 0)
            _catastroRefcat14 = State(initialValue: "")
            _catastroAreaValue = State(initialValue: nil)
            _catastroAreaUom = State(initialValue: nil)
            _catastroLabel = State(initialValue: nil)
            _catastroRings = State(initialValue: [])
            _selectedGroup = State(initialValue: nil)

        case .edit(let land):
            let normalizedProductionType = ProductionCatalog.item(for: land.productionType)?.name ?? land.productionType
            let subtypeOptions = ProductionCatalog.item(for: normalizedProductionType)?.varieties ?? []
            let usesCustomSubtype = !land.productionSubtype.isEmpty && !subtypeOptions.contains(land.productionSubtype)

            _name = State(initialValue: land.name)
            _activityType = State(initialValue: land.activityType.isEmpty ? ActivityCatalog.defaultName : land.activityType)
            _productionType = State(initialValue: normalizedProductionType)
            _productionSubtype = State(initialValue: usesCustomSubtype ? ProductionCatalog.other : land.productionSubtype)
            _customSubtype = State(initialValue: usesCustomSubtype ? land.productionSubtype : "")
            _sizeAcres = State(initialValue: land.sizeAcres)
            _incomeAnnual = State(initialValue: land.incomeAnnual)
            _annualIrrigationCost = State(initialValue: land.annualIrrigationCost)
            _annualFertilizerCost = State(initialValue: land.annualFertilizerCost)
            _annualLaborCost = State(initialValue: land.annualLaborCost)
            _annualMaintenanceCost = State(initialValue: land.annualMaintenanceCost)
            _latitude = State(initialValue: land.latitude)
            _longitude = State(initialValue: land.longitude)
            _notes = State(initialValue: land.notes)
            _installedCapacityKW = State(initialValue: land.installedCapacityKW)
            _annualElectricityProductionKWh = State(initialValue: land.annualElectricityProductionKWh)
            _selfConsumptionRate = State(initialValue: land.selfConsumptionRate)
            _gridExportRate = State(initialValue: land.gridExportRate)
            _catastroRefcat14 = State(initialValue: land.catastroRefcat14 ?? "")
            _catastroAreaValue = State(initialValue: land.catastroAreaValue)
            _catastroAreaUom = State(initialValue: land.catastroAreaUom)
            _catastroLabel = State(initialValue: land.catastroLabel)
            _catastroRings = State(initialValue: land.catastroRings)
            _selectedGroup = State(initialValue: land.group)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    identityCard

                    if isEnergyActivity {
                        energyMetricsCard
                    }

                    if showsCropCatalog {
                        cropConfigurationCard
                    }

                    catastroCard

                    if catastroRings.isEmpty {
                        locationCard
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
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
            .onChange(of: productionType) { _, _ in
                productionSubtype = ""
                customSubtype = ""
            }
            .onChange(of: activityType) { _, newValue in
                guard !ActivityCatalog.supportsCropCatalog(activityType: newValue) else { return }
                productionType = ""
                productionSubtype = ""
                customSubtype = ""
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.9), value: activityType)
            .animation(.spring(response: 0.34, dampingFraction: 0.9), value: productionType)
            .animation(.spring(response: 0.34, dampingFraction: 0.9), value: showingGroupPicker)
            .sheet(isPresented: $showingNewGroup) {
                GroupEditorView()
            }
            .overlay {
                if showingGroupPicker {
                    groupPickerOverlay
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .create:
            return language.localized("New Land", "Nuevo terreno")
        case .edit:
            return language.localized("Edit Land", "Editar terreno")
        }
    }

    private var identityCard: some View {
        editorCard(
            title: "",
            subtitle: "",
            systemImage: "leaf.circle.fill",
            tint: Color(red: 0.21, green: 0.68, blue: 0.43)
        ) {
            editorFieldShell(
                label: language.localized("Land name", "Nombre del terreno"),
                systemImage: "character.textbox",
                tint: .blue
            ) {
                TextField(
                    language.localized("Example: South orchard", "Ejemplo: Huerto sur"),
                    text: $name
                )
                .textInputAutocapitalization(.words)
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel(
                    language.localized("Land type", "Tipo de terreno"),
                    systemImage: "square.grid.2x2.fill",
                    tint: activityTint(for: activityType)
                )

                VStack(spacing: 10) {
                    ForEach(ActivityCatalog.items) { item in
                        GlassSelectionCard(
                            title: item.displayName(language: language),
                            subtitle: item.includesEnergyMetrics
                                ? language.localized("Compatible with energy metrics", "Compatible con métricas energéticas")
                                : language.localized("Agricultural or mixed use land", "Terreno agrícola o mixto"),
                            systemImage: activitySymbol(for: item.name),
                            tint: activityTint(for: item.name),
                            isSelected: activityType == item.name
                        ) {
                            activityType = item.name
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var cropConfigurationCard: some View {
        editorCard(
            title: "",
            subtitle: "",
            systemImage: "leaf.fill",
            tint: productionTint(for: productionType)
        ) {
            cropCatalogSection

            if !productionType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                varietySelectionSection
                    .transition(editorRevealTransition)
            }

            if productionSubtype == ProductionCatalog.other {
                editorFieldShell(
                    label: language.localized("Custom variety", "Variedad personalizada"),
                    systemImage: "sparkles",
                    tint: productionTint(for: productionType)
                ) {
                    TextField(
                        language.localized("Write the variety name", "Escribe el nombre de la variedad"),
                        text: $customSubtype
                    )
                    .textInputAutocapitalization(.words)
                }
                    .transition(editorRevealTransition)
            }

            groupSelectionSection
        }
    }

    private var energyMetricsCard: some View {
        editorCard(
            title: language.localized("Electric Generation", "Generación eléctrica"),
            subtitle: language.localized("Only visible when the selected land type supports energy production.", "Solo aparece cuando el tipo de terreno seleccionado admite producción energética."),
            systemImage: "bolt.circle.fill",
            tint: Color(red: 0.95, green: 0.71, blue: 0.16)
        ) {
            LazyVGrid(columns: metricGridColumns, spacing: 12) {
                editorMetricField(
                    label: language.localized("Installed Capacity (kW)", "Potencia instalada (kW)"),
                    systemImage: "bolt.fill",
                    tint: Color(red: 0.97, green: 0.76, blue: 0.16),
                    value: $installedCapacityKW
                )

                editorMetricField(
                    label: language.localized("Electricity Production (kWh/year)", "Producción eléctrica (kWh/año)"),
                    systemImage: "gauge.with.dots.needle.50percent",
                    tint: Color(red: 0.25, green: 0.55, blue: 0.95),
                    value: $annualElectricityProductionKWh
                )

                editorMetricField(
                    label: language.localized("Self Consumption (%)", "Autoconsumo (%)"),
                    systemImage: "house.fill",
                    tint: Color(red: 0.22, green: 0.72, blue: 0.46),
                    value: $selfConsumptionRate
                )

                editorMetricField(
                    label: language.localized("Grid Export (%)", "Vertido a red (%)"),
                    systemImage: "arrow.up.forward.circle.fill",
                    tint: Color(red: 0.96, green: 0.49, blue: 0.18),
                    value: $gridExportRate
                )
            }
        }
    }

    private var editorRevealTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }

    private var cropCatalogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(
                language.localized("Crop group", "Grupo de cultivo"),
                systemImage: "leaf.fill",
                tint: productionTint(for: productionType)
            )

            Text(
                language.localized(
                    "Choose a broad family first, like vegetables, fruit trees or cereals.",
                    "Primero elige una familia amplia, como hortalizas, frutales o cereales."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(ProductionCatalog.items) { item in
                        GlassSelectionCard(
                            title: item.displayName(language: language),
                            subtitle: "\(item.varieties.count - 1) " + language.localized("options available", "opciones disponibles"),
                            systemImage: productionSymbol(for: item.name),
                            tint: Color(hex: item.colorHex),
                            isSelected: productionType == item.name
                        ) {
                            productionType = item.name
                        }
                        .frame(width: horizontalSelectionCardWidth)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var varietySelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(
                language.localized("Crop / variety", "Cultivo / variedad"),
                systemImage: "sparkles",
                tint: productionTint(for: productionType)
            )

            if subtypeOptions.isEmpty {
                Text(
                    language.localized(
                        "Select a crop group first to see the compatible options.",
                        "Selecciona primero un grupo de cultivo para ver las opciones compatibles."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(subtypeOptions, id: \.self) { subtype in
                            GlassSelectionCard(
                                title: ProductionCatalog.displayVarietyName(for: subtype, language: language),
                                subtitle: subtype == ProductionCatalog.other
                                    ? language.localized("Custom option", "Opción personalizada")
                                    : language.localized("Available in Spain", "Disponible en España"),
                                systemImage: subtype == ProductionCatalog.other ? "ellipsis.circle.fill" : productionSymbol(for: productionType),
                                tint: productionTint(for: productionType),
                                isSelected: productionSubtype == subtype
                            ) {
                                productionSubtype = subtype
                            }
                            .frame(width: horizontalSelectionCardWidth)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private var groupSelectionSection: some View {
        let groupTint = Color(red: 0.54, green: 0.45, blue: 0.93)

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel(
                language.localized("Group", "Grupo"),
                systemImage: "person.3.sequence.fill",
                tint: groupTint
            )

            Button {
                withAnimation {
                    showingGroupPicker = true
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selectedGroup?.name ?? language.localized("No group selected", "Ningún grupo seleccionado"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(selectedGroup == nil ? .secondary : .primary)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(groupTint.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                if let selectedGroup {
                    Text(selectedGroup.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(groupTint)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(groupTint.opacity(0.12), in: Capsule())
                }

                Button {
                    showingNewGroup = true
                } label: {
                    Text(language.localized("New Group", "Nuevo grupo"))
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(groupTint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var groupPickerOverlay: some View {
        let groupTint = Color(red: 0.54, green: 0.45, blue: 0.93)

        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    closeGroupPicker()
                }

            GroupPickerGlassSheet(
                language: language,
                tint: groupTint,
                groups: groups,
                selectedGroupID: selectedGroup?.id,
                onSelectNone: {
                    selectedGroup = nil
                    closeGroupPicker()
                },
                onSelectGroup: { group in
                    selectedGroup = group
                    closeGroupPicker()
                },
                onCreateGroup: {
                    closeGroupPicker()
                    DispatchQueue.main.async {
                        showingNewGroup = true
                    }
                },
                onClose: closeGroupPicker
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .zIndex(1)
    }

    private var catastroCard: some View {
        editorCard(
            title: language.localized("Catastro (Spain)", "Catastro (España)"),
            subtitle: language.localized("Fetch parcel geometry and metadata directly from the cadastral reference.", "Obtén la geometría y los metadatos de la parcela directamente desde la referencia catastral."),
            systemImage: "map.circle.fill",
            tint: Color(red: 0.14, green: 0.56, blue: 0.96)
        ) {
            editorFieldShell(
                label: language.localized("REFCAT (14 chars)", "REFCAT (14 caracteres)"),
                systemImage: "number",
                tint: Color(red: 0.14, green: 0.56, blue: 0.96)
            ) {
                TextField("", text: $catastroRefcat14)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            if isFetchingCatastro {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(language.localized("Fetching parcel...", "Obteniendo parcela..."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    Task { await fetchCatastro() }
                } label: {
                    Label(language.localized("Fetch Parcel", "Buscar parcela"), systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.14, green: 0.56, blue: 0.96))
                .disabled(catastroRefcat14.trimmingCharacters(in: .whitespacesAndNewlines).count != 14)
            }

            if let catastroError {
                Text(catastroError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if catastroLabel != nil || catastroAreaValue != nil || !catastroRings.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        catastroSummaryPills
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        catastroSummaryPills
                    }
                }
            }
        }
    }

    private var locationCard: some View {
        editorCard(
            title: language.localized("Location", "Ubicación"),
            subtitle: language.localized(
                "Search an address or tap the map to set this land's position manually.",
                "Busca una dirección o toca el mapa para fijar la posición de este terreno manualmente."
            ),
            systemImage: "mappin.circle.fill",
            tint: Color(red: 0.86, green: 0.23, blue: 0.27)
        ) {
            LandLocationPickerCard(latitude: $latitude, longitude: $longitude, language: language)
        }
    }

    @ViewBuilder
    private var catastroSummaryPills: some View {
        if let catastroLabel {
            GradientInfoPill(
                title: language.localized("Label", "Etiqueta"),
                value: catastroLabel,
                systemImage: "tag.fill",
                colors: [Color(red: 0.08, green: 0.46, blue: 0.88), Color(red: 0.14, green: 0.56, blue: 0.96)]
            )
        }

        if let catastroAreaValue {
            GradientInfoPill(
                title: language.localized("Area", "Superficie"),
                value: catastroAreaValue.formatted(.number.precision(.fractionLength(2))) + " " + (catastroAreaUom ?? ""),
                systemImage: "square.expand",
                colors: [Color(red: 0.95, green: 0.65, blue: 0.18), Color(red: 0.90, green: 0.42, blue: 0.28)]
            )
        }
    }

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var metricGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 152), spacing: 12)]
    }

    private var horizontalSelectionCardWidth: CGFloat {
        228
    }

    private var showsCropCatalog: Bool {
        ActivityCatalog.supportsCropCatalog(activityType: activityType)
    }

    private var canSave: Bool {
        let nameOk = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let activityOk = !activityType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let cropOk = !showsCropCatalog || (
            !productionType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !effectiveSubtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        return nameOk && activityOk && cropOk
    }

    private var subtypeOptions: [String] {
        showsCropCatalog ? (ProductionCatalog.item(for: productionType)?.varieties ?? []) : []
    }

    private var effectiveSubtype: String {
        if productionSubtype == ProductionCatalog.other {
            return customSubtype
        }
        return productionSubtype
    }

    private var isEnergyActivity: Bool {
        ActivityCatalog.supportsEnergyMetrics(activityType: activityType)
    }

    private var persistedInstalledCapacityKW: Double {
        isEnergyActivity ? max(0, installedCapacityKW) : 0
    }

    private var persistedAnnualIrrigationCost: Double {
        max(0, annualIrrigationCost)
    }

    private var persistedAnnualFertilizerCost: Double {
        max(0, annualFertilizerCost)
    }

    private var persistedAnnualLaborCost: Double {
        max(0, annualLaborCost)
    }

    private var persistedAnnualMaintenanceCost: Double {
        max(0, annualMaintenanceCost)
    }

    private var persistedAnnualElectricityKWh: Double {
        isEnergyActivity ? max(0, annualElectricityProductionKWh) : 0
    }

    private var persistedSelfConsumptionRate: Double {
        isEnergyActivity ? clampedPercentage(selfConsumptionRate) : 0
    }

    private var persistedGridExportRate: Double {
        isEnergyActivity ? clampedPercentage(gridExportRate) : 0
    }

    private func save() {
        let landID: UUID

        switch mode {
        case .create:
            let land = Land(
                name: name,
                latitude: latitude,
                longitude: longitude,
                sizeAcres: sizeAcres,
                activityType: activityType,
                productionType: productionType,
                productionSubtype: effectiveSubtype,
                incomeAnnual: incomeAnnual,
                annualIrrigationCost: persistedAnnualIrrigationCost,
                annualFertilizerCost: persistedAnnualFertilizerCost,
                annualLaborCost: persistedAnnualLaborCost,
                annualMaintenanceCost: persistedAnnualMaintenanceCost,
                notes: notes,
                installedCapacityKW: persistedInstalledCapacityKW,
                annualElectricityProductionKWh: persistedAnnualElectricityKWh,
                selfConsumptionRate: persistedSelfConsumptionRate,
                gridExportRate: persistedGridExportRate,
                catastroRefcat14: catastroRefcat14.isEmpty ? nil : catastroRefcat14,
                catastroAreaValue: catastroAreaValue,
                catastroAreaUom: catastroAreaUom,
                catastroLabel: catastroLabel,
                catastroRings: catastroRings,
                catastroFetchedAt: catastroRings.isEmpty ? nil : Date(),
                group: selectedGroup
            )
            context.insert(land)
            landID = land.id

        case .edit(let land):
            land.name = name
            land.activityType = activityType
            land.productionType = productionType
            land.productionSubtype = effectiveSubtype
            land.sizeAcres = sizeAcres
            land.incomeAnnual = incomeAnnual
            land.annualIrrigationCost = persistedAnnualIrrigationCost
            land.annualFertilizerCost = persistedAnnualFertilizerCost
            land.annualLaborCost = persistedAnnualLaborCost
            land.annualMaintenanceCost = persistedAnnualMaintenanceCost
            land.latitude = latitude
            land.longitude = longitude
            land.notes = notes
            land.installedCapacityKW = persistedInstalledCapacityKW
            land.annualElectricityProductionKWh = persistedAnnualElectricityKWh
            land.selfConsumptionRate = persistedSelfConsumptionRate
            land.gridExportRate = persistedGridExportRate
            land.catastroRefcat14 = catastroRefcat14.isEmpty ? nil : catastroRefcat14
            land.catastroAreaValue = catastroAreaValue
            land.catastroAreaUom = catastroAreaUom
            land.catastroLabel = catastroLabel
            land.catastroRings = catastroRings
            land.catastroFetchedAt = catastroRings.isEmpty ? nil : Date()
            land.group = selectedGroup
            land.touchUpdatedAt()
            landID = land.id
        }

        try? context.save()
        Task { @MainActor in
            await SupabaseSyncService.shared.queueLandUpsert(id: landID, context: context)
        }
        dismiss()
    }

    private func clampedPercentage(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private func closeGroupPicker() {
        withAnimation {
            showingGroupPicker = false
        }
    }

    private func fetchCatastro() async {
        isFetchingCatastro = true
        catastroError = nil
        defer { isFetchingCatastro = false }

        do {
            let parcel = try await CatastroService.shared.fetchParcel(refcat14: catastroRefcat14)
            catastroRefcat14 = parcel.refcat ?? catastroRefcat14
            catastroAreaValue = parcel.areaValue
            catastroAreaUom = parcel.areaUom
            catastroLabel = parcel.label
            catastroRings = parcel.rings

            if let centroid = centroid(from: parcel.rings) {
                latitude = centroid.latitude
                longitude = centroid.longitude
            }

            if let areaValue = parcel.areaValue {
                sizeAcres = areaValue / 4046.8564224
            }

            switch mode {
            case .create:
                break

            case .edit(let land):
                land.catastroRefcat14 = parcel.refcat ?? catastroRefcat14
                land.catastroAreaValue = catastroAreaValue
                land.catastroAreaUom = catastroAreaUom
                land.catastroLabel = catastroLabel
                land.catastroRings = catastroRings
                land.catastroFetchedAt = Date()

                if let centroid = centroid(from: parcel.rings) {
                    land.latitude = centroid.latitude
                    land.longitude = centroid.longitude
                }

                land.touchUpdatedAt()
            }
        } catch {
            catastroError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func centroid(from rings: [[Coordinate]]) -> Coordinate? {
        guard let ring = rings.first, !ring.isEmpty else { return nil }

        var minLat = ring[0].latitude
        var maxLat = ring[0].latitude
        var minLon = ring[0].longitude
        var maxLon = ring[0].longitude

        for coord in ring {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        return Coordinate(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    }

    @ViewBuilder
    private func editorCard<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty || !subtitle.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        if !title.isEmpty {
                            Text(title)
                                .font(.headline.weight(.semibold))
                        }

                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func editorFieldShell<Content: View>(
        label: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label, systemImage: systemImage, tint: tint)

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

    @ViewBuilder
    private func editorMetricField(
        label: String,
        systemImage: String,
        tint: Color,
        value: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label, systemImage: systemImage, tint: tint)

            TextField("", value: value, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
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

    @ViewBuilder
    private func sectionLabel(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }

    private func activitySymbol(for type: String) -> String {
        switch type {
        case ActivityCatalog.agricultural:
            return "leaf.circle.fill"
        case ActivityCatalog.agrovoltaic:
            return "bolt.badge.a.fill"
        case ActivityCatalog.electricGeneration:
            return "bolt.circle.fill"
        case "Livestock":
            return "pawprint.fill"
        case "Forestry":
            return "tree.fill"
        case "Mixed Use":
            return "square.grid.2x2.fill"
        default:
            return "square.grid.2x2.fill"
        }
    }

    private func activityTint(for type: String) -> Color {
        switch type {
        case ActivityCatalog.agricultural:
            return Color(red: 0.20, green: 0.66, blue: 0.39)
        case ActivityCatalog.agrovoltaic:
            return Color(red: 0.16, green: 0.54, blue: 0.93)
        case ActivityCatalog.electricGeneration:
            return Color(red: 0.96, green: 0.66, blue: 0.16)
        case "Livestock":
            return Color(red: 0.78, green: 0.43, blue: 0.24)
        case "Forestry":
            return Color(red: 0.17, green: 0.55, blue: 0.31)
        case "Mixed Use":
            return Color(red: 0.51, green: 0.47, blue: 0.90)
        default:
            return Color(red: 0.08, green: 0.46, blue: 0.88)
        }
    }

    private func productionSymbol(for type: String) -> String {
        switch ProductionCatalog.item(for: type)?.name {
        case ProductionCatalog.vegetables:
            return "leaf.fill"
        case ProductionCatalog.melonsAndWatermelons:
            return "drop.fill"
        case ProductionCatalog.cereals:
            return "circle.grid.3x3.fill"
        case ProductionCatalog.legumes:
            return "square.grid.2x2.fill"
        case ProductionCatalog.industrialCrops:
            return "gearshape.fill"
        case ProductionCatalog.forageCrops:
            return "leaf.circle.fill"
        case ProductionCatalog.citrus:
            return "sun.max.fill"
        case ProductionCatalog.stoneFruits,
            ProductionCatalog.pomeFruits,
            ProductionCatalog.nuts,
            ProductionCatalog.tropicalFruits,
            ProductionCatalog.otherFruitTrees:
            return "tree.fill"
        case ProductionCatalog.berries:
            return "drop.circle.fill"
        case ProductionCatalog.vineyard:
            return "wineglass.fill"
        case ProductionCatalog.oliveGrove:
            return "leaf.fill"
        case ProductionCatalog.flowersAndOrnamentals:
            return "sparkles"
        default:
            return "leaf.fill"
        }
    }

    private func productionTint(for type: String) -> Color {
        if let item = ProductionCatalog.item(for: type) {
            return Color(hex: item.colorHex)
        }

        return Color(red: 0.17, green: 0.63, blue: 0.40)
    }
}

private struct GroupPickerGlassSheet: View {
    let language: AppLanguage
    let tint: Color
    let groups: [LandGroup]
    let selectedGroupID: UUID?
    let onSelectNone: () -> Void
    let onSelectGroup: (LandGroup) -> Void
    let onCreateGroup: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label(language.localized("Assign group", "Asignar grupo"), systemImage: "person.3.sequence.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(
                language.localized(
                    "Choose where this land should be grouped. This selector stays fixed so it does not jump around the screen.",
                    "Elige a qué grupo debe asociarse este terreno. Este selector queda fijo para que no salte a otra zona de la pantalla."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                selectionRow(
                    title: language.localized("No group", "Sin grupo"),
                    subtitle: language.localized("The land will stay ungrouped for now.", "El terreno quedará sin grupo por ahora."),
                    tint: Color.secondary.opacity(0.65),
                    isSelected: selectedGroupID == nil,
                    action: onSelectNone
                )

                if groups.isEmpty {
                    Text(language.localized("There are no groups created yet.", "Todavía no hay grupos creados."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(groups) { group in
                                selectionRow(
                                    title: group.name,
                                    subtitle: "\(group.lands.count) " + language.localized("lands", "terrenos"),
                                    tint: Color(hex: group.colorHex),
                                    isSelected: selectedGroupID == group.id,
                                    action: {
                                        onSelectGroup(group)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .frame(maxHeight: min(CGFloat(groups.count) * 74, 320))
                }
            }

            Button(action: onCreateGroup) {
                Label(language.localized("New group", "Nuevo grupo"), systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
    }

    private func selectionRow(
        title: String,
        subtitle: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(tint.opacity(isSelected ? 0.95 : 0.45))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? tint : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.28) : Color.white.opacity(0.38), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
