import SwiftUI
import MapKit
import SwiftData
import Charts

struct LandDetailView: View {
    private enum DeviceComposerStep: String, CaseIterable, Identifiable {
        case name
        case type
        case link
        case bluetooth
        case summary

        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @AppStorage(AccountPreferences.measurementSystemKey) private var measurementSystemRaw = AppSettings.defaultMeasurementSystem.rawValue
    @AppStorage(AccountPreferences.preferredCurrencyCodeKey) private var preferredCurrencyCode = AppSettings.defaultCurrency.rawValue
    let land: Land
    @State private var showingEdit = false
    @State private var showingDelete = false
    @State private var showingCreateHistoryEditor = false
    @State private var showingEditHistoryEditor = false
    @State private var editingHistoryEntryID: UUID?
    @State private var pendingDeleteHistoryEntry: LandHistoryEntry?
    @State private var showingCreateTaskEditor = false
    @State private var showingEditTaskEditor = false
    @State private var editingTaskID: UUID?
    @State private var pendingDeleteTask: LandTask?
    @State private var selectedTimelineMetric: TimelineMetric = .income
    @State private var selectedTaskFilter: LandTaskFilter = .pending
    @State private var showingExpenseEditor = false
    @State private var showingDeviceComposer = false
    @State private var deviceName = ""
    @State private var deviceType: LandDeviceType = .thermometer
    @State private var deviceLinkMethod: LandDeviceLinkMethod = .bluetooth
    @State private var deviceComposerStep: DeviceComposerStep = .type
    @StateObject private var bluetoothPairingService = BluetoothPairingService()
    @State private var latestTelemetryByDeviceID: [UUID: IoTTelemetryRecord] = [:]
    @State private var isRefreshingTelemetry = false
    @State private var telemetryLastSyncAt: Date?
    @State private var isCostsExpanded = false
    @State private var isOperationsExpanded = false
    @State private var showingPairingAssistant = false
    @State private var showingDetailsSheet = false

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var measurementSystem: AppMeasurementSystem {
        AppSettings.measurementSystem(from: measurementSystemRaw)
    }

    private var currencyCode: String {
        AppSettings.currencyCode(from: preferredCurrencyCode)
    }

    private var canViewEconomics: Bool {
        roleAccessViewModel.canViewEconomics
    }

    private var canManageStructure: Bool {
        roleAccessViewModel.canManageStructure
    }

    private var supportsEnergyMetrics: Bool {
        ActivityCatalog.supportsEnergyMetrics(activityType: land.activityType)
    }

    private var isAgrovoltaicLand: Bool {
        ActivityCatalog.item(for: land.activityType)?.name == ActivityCatalog.agrovoltaic
    }

    private var netMarginColor: Color {
        land.annualNetMargin >= 0 ? .green : .red
    }

    private var mapAccentColor: Color {
        canViewEconomics ? netMarginColor : Color.blue
    }

    private var expenseRatioRaw: Double {
        let income = max(0, land.incomeAnnual)
        guard income > 0 else { return land.annualTotalExpenses > 0 ? 1 : 0 }
        return max(0, land.annualTotalExpenses / income)
    }

    private var expenseRatioProgress: Double {
        min(1, expenseRatioRaw)
    }

    private var expenseRatioText: String {
        let percent = expenseRatioRaw * 100
        return "\(percent.formatted(.number.precision(.fractionLength(1))))%"
    }

    private var subtypeOrDash: String {
        let trimmed = land.productionSubtype.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private var localizedActivityType: String {
        ActivityCatalog.displayName(for: land.activityType, language: language)
    }

    private var localizedProductionType: String {
        ProductionCatalog.displayName(for: land.productionType, language: language)
    }

    private var localizedSubtypeOrDash: String {
        subtypeOrDash == "-"
            ? "-"
            : ProductionCatalog.displayVarietyName(for: subtypeOrDash, language: language)
    }

    private var hasEnergyConfiguration: Bool {
        land.installedCapacityKW > 0 || land.annualElectricityProductionKWh > 0
    }

    private var hasCadastreFootprint: Bool {
        land.catastroRefcat14 != nil || !land.catastroRings.flatMap { $0 }.isEmpty
    }

    private var projectLensTitle: String {
        if supportsEnergyMetrics && hasEnergyConfiguration {
            return isAgrovoltaicLand
                ? language.localized("Operational Agrovoltaic Parcel", "Parcela agrovoltaica operativa")
                : language.localized("Energy-Enabled Parcel", "Parcela con capa energética")
        }

        if supportsEnergyMetrics {
            return isAgrovoltaicLand
                ? language.localized("Agrovoltaic Candidate", "Candidata agrovoltaica")
                : language.localized("Dual-Use Candidate", "Candidata de doble uso")
        }

        return language.localized("Baseline Agricultural Parcel", "Parcela agrícola base")
    }

    private var projectLensSubtitle: String {
        if supportsEnergyMetrics && hasEnergyConfiguration {
            return language.localized(
                "This record already combines crop and energy inputs in one parcel view.",
                "Este registro ya combina cultivo y energía dentro de una sola vista de parcela."
            )
        }

        if supportsEnergyMetrics {
            return language.localized(
                "The parcel is ready to be evaluated as a crop + energy project with the current backend.",
                "La parcela ya puede evaluarse como proyecto cultivo + energía con el backend actual."
            )
        }

        return language.localized(
            "You can keep building field evidence here before enabling the agrovoltaic layer.",
            "Aquí puedes seguir construyendo evidencia de campo antes de activar la capa agrovoltaica."
        )
    }

    private var projectLensFooter: String {
        if supportsEnergyMetrics && hasEnergyConfiguration {
            return language.localized(
                "The next backend step is optional: only zone-by-zone comparisons or design scenarios would require new tables.",
                "El siguiente paso de backend es opcional: solo comparativas por zonas o escenarios de diseño exigirían nuevas tablas."
            )
        }

        if supportsEnergyMetrics {
            return language.localized(
                "Add capacity, annual production, historical records and sensors to turn this candidate into a justified project.",
                "Añade potencia, producción anual, histórico y sensores para convertir esta candidata en un proyecto justificable."
            )
        }

        return language.localized(
            "Switching the activity to Agrovoltaic later will not break the current model; it only unlocks the existing energy fields.",
            "Cambiar la actividad a Agrovoltaica más adelante no rompe el modelo actual; solo activa los campos energéticos ya existentes."
        )
    }

    private var expenseItems: [ExpenseItem] {
        [
            ExpenseItem(
                id: "irrigation",
                title: language.localized("Irrigation", "Riego"),
                amount: max(0, land.annualIrrigationCost),
                color: Color(red: 0.16, green: 0.46, blue: 0.95)
            ),
            ExpenseItem(
                id: "fertilizer",
                title: language.localized("Fertilizer", "Fertilizantes"),
                amount: max(0, land.annualFertilizerCost),
                color: Color(red: 0.22, green: 0.73, blue: 0.39)
            ),
            ExpenseItem(
                id: "labor",
                title: language.localized("Labor", "Mano de obra"),
                amount: max(0, land.annualLaborCost),
                color: Color(red: 0.95, green: 0.58, blue: 0.20)
            ),
            ExpenseItem(
                id: "maintenance",
                title: language.localized("Maintenance", "Mantenimiento"),
                amount: max(0, land.annualMaintenanceCost),
                color: Color(red: 0.89, green: 0.29, blue: 0.32)
            )
        ]
    }

    private var historyEntriesAscending: [LandHistoryEntry] {
        land.historyEntries.sorted { lhs, rhs in
            if lhs.periodKey == rhs.periodKey {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.periodKey < rhs.periodKey
        }
    }

    private var historyEntriesDescending: [LandHistoryEntry] {
        Array(historyEntriesAscending.reversed())
    }

    private var chartEntries: [LandHistoryEntry] {
        Array(historyEntriesAscending.suffix(24))
    }

    private var editingHistoryEntry: LandHistoryEntry? {
        guard let editingHistoryEntryID else { return nil }
        return land.historyEntries.first { $0.id == editingHistoryEntryID }
    }

    private var tasksAscending: [LandTask] {
        land.tasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }
            if lhs.dueDate == rhs.dueDate {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.dueDate < rhs.dueDate
        }
    }

    private var filteredTasks: [LandTask] {
        tasksAscending.filter { selectedTaskFilter.matches(task: $0, now: Date()) }
    }

    private var editingTask: LandTask? {
        guard let editingTaskID else { return nil }
        return land.tasks.first { $0.id == editingTaskID }
    }

    private var devices: [LandDevice] {
        land.devices.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var canAddDevice: Bool {
        let hasName = !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasName else { return false }

        if deviceLinkMethod == .bluetooth {
            return bluetoothPairingService.connectedDevice != nil
        }

        return true
    }

    private var deviceComposerSteps: [DeviceComposerStep] {
        var steps: [DeviceComposerStep] = [.type, .link]
        if deviceLinkMethod == .bluetooth {
            steps.append(.bluetooth)
        }
        steps.append(.summary)
        return steps
    }

    private var deviceComposerStepIndex: Int {
        deviceComposerSteps.firstIndex(of: deviceComposerStep) ?? 0
    }

    private var deviceComposerProgress: Double {
        guard !deviceComposerSteps.isEmpty else { return 0 }
        return Double(deviceComposerStepIndex + 1) / Double(deviceComposerSteps.count)
    }

    private var isLastDeviceComposerStep: Bool {
        deviceComposerStep == deviceComposerSteps.last
    }

    private var canAdvanceFromCurrentDeviceComposerStep: Bool {
        switch deviceComposerStep {
        case .name:
            return !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .type, .link:
            return true
        case .bluetooth:
            return bluetoothPairingService.connectedDevice != nil
        case .summary:
            return canAddDevice
        }
    }

    private var deviceComposerPageHeight: CGFloat {
        switch deviceComposerStep {
        case .name:
            return 190
        case .type:
            return 470
        case .link:
            return 390
        case .bluetooth:
            return bluetoothComposerPageHeight
        case .summary:
            return summaryComposerPageHeight
        }
    }

    private var bluetoothComposerPageHeight: CGFloat {
        if bluetoothPairingService.discoveredDevices.isEmpty {
            if bluetoothPairingService.connectedDevice != nil ||
                bluetoothPairingService.isConnecting ||
                bluetoothPairingService.latestSample != nil ||
                bluetoothPairingService.lastError != nil ||
                !bluetoothPairingService.isBluetoothReady {
                return 360
            }

            return 280
        }

        return 620
    }

    private var summaryComposerPageHeight: CGFloat {
        if deviceLinkMethod == .bluetooth && bluetoothPairingService.connectedDevice == nil {
            return 340
        }

        if deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return 300
        }

        return 270
    }

    private var scheduledTaskDates: [Date] {
        tasksAscending.flatMap { task -> [Date] in
            guard !task.isCompleted else { return [Date]() }
            var dates: [Date] = [task.dueDate]
            if let reminderDate = task.reminderDate {
                dates.append(reminderDate)
            }
            return dates
        }
    }

    private func deviceTypeDescription(_ type: LandDeviceType) -> String {
        switch type {
        case .thermometer:
            return language.localized("Ambient or soil temperature", "Temperatura ambiente o del suelo")
        case .waterPump:
            return language.localized("Flow and pumping activity", "Caudal y actividad de bombeo")
        case .rainGauge:
            return language.localized("Rainfall collection", "Recogida de lluvia")
        case .humiditySensor:
            return language.localized("Humidity and moisture", "Humedad y humedad relativa")
        case .pressureSensor:
            return language.localized("Pressure lines and valves", "Líneas y válvulas de presión")
        case .energyMeter:
            return language.localized("Consumption and energy use", "Consumo y uso energético")
        case .inverter:
            return language.localized("Solar or power conversion", "Conversión solar o eléctrica")
        case .other:
            return language.localized("Custom telemetry source", "Fuente de telemetría personalizada")
        }
    }

    private func deviceTypeTint(_ type: LandDeviceType) -> Color {
        switch type {
        case .thermometer:
            return Color(red: 0.18, green: 0.54, blue: 0.96)
        case .waterPump:
            return Color(red: 0.06, green: 0.63, blue: 0.78)
        case .rainGauge:
            return Color(red: 0.27, green: 0.57, blue: 0.92)
        case .humiditySensor:
            return Color(red: 0.21, green: 0.70, blue: 0.46)
        case .pressureSensor:
            return Color(red: 0.98, green: 0.62, blue: 0.18)
        case .energyMeter:
            return Color(red: 0.96, green: 0.76, blue: 0.17)
        case .inverter:
            return Color(red: 0.93, green: 0.50, blue: 0.17)
        case .other:
            return Color(red: 0.55, green: 0.49, blue: 0.95)
        }
    }

    private func linkMethodDescription(_ method: LandDeviceLinkMethod) -> String {
        switch method {
        case .bluetooth:
            return language.localized("Nearby pairing on site", "Enlace cercano en la finca")
        case .cloudAPI:
            return language.localized("Device syncs through internet", "El dispositivo sincroniza por internet")
        case .mqttGateway:
            return language.localized("Sensor to gateway to app", "Sensor a pasarela y luego a la app")
        case .manual:
            return language.localized("Create now and link later", "Crear ahora y enlazar más tarde")
        }
    }

    private func linkMethodTint(_ method: LandDeviceLinkMethod) -> Color {
        switch method {
        case .bluetooth:
            return Color(red: 0.18, green: 0.54, blue: 0.96)
        case .cloudAPI:
            return Color(red: 0.33, green: 0.59, blue: 0.98)
        case .mqttGateway:
            return Color(red: 0.20, green: 0.70, blue: 0.55)
        case .manual:
            return Color(red: 0.52, green: 0.52, blue: 0.58)
        }
    }

    var body: some View {
        alertConfiguredContent
    }

    private var baseContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapCard
                projectLensCard

                if canViewEconomics {
                    costsSectionCard
                }

                operationsSectionCard

                if !land.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    notesCard
                }
            }
            .padding(16)
            .padding(.bottom, 62)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottomLeading) {
            detailsFloatingButton
        }
        .clipped()
        .navigationTitle(land.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManageStructure {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        showingEdit = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private var lifecycleConfiguredContent: some View {
        baseContent
            .task(id: land.id) {
                await backfillIoTDevicesIfNeeded()
                await refreshLatestTelemetry()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    await refreshLatestTelemetry()
                }
            }
            .onChange(of: deviceType) { _, newType in
                deviceLinkMethod = IoTDeviceLinkService.shared.recommendedMethod(for: newType)
            }
            .onChange(of: deviceLinkMethod) { _, newMethod in
                syncDeviceComposerStepForCurrentMethod()
                if newMethod == .bluetooth {
                    startBluetoothScanIfNeeded()
                } else {
                    bluetoothPairingService.stopScanning()
                }
            }
            .onChange(of: showingDeviceComposer) { _, isShowing in
                if isShowing {
                    syncDeviceComposerStepForCurrentMethod()
                    startBluetoothScanIfNeeded()
                } else {
                    bluetoothPairingService.stopScanning()
                }
            }
            .onChange(of: bluetoothPairingService.connectedDeviceID) { _, _ in
                guard
                    deviceLinkMethod == .bluetooth,
                    let connectedDevice = bluetoothPairingService.connectedDevice,
                    deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return
                }

                deviceName = connectedDevice.name
            }
            .onDisappear {
                bluetoothPairingService.stopScanning()
            }
    }

    private var sheetConfiguredContent: some View {
        lifecycleConfiguredContent
            .sheet(isPresented: $showingEdit) {
                LandEditorView(mode: .edit(land))
            }
            .sheet(isPresented: $showingCreateHistoryEditor) {
                NavigationStack {
                    HistoryEntryEditorView(mode: .create(land))
                }
            }
            .sheet(isPresented: $showingEditHistoryEditor, onDismiss: {
                editingHistoryEntryID = nil
            }) {
                NavigationStack {
                    if let entry = editingHistoryEntry {
                        HistoryEntryEditorView(mode: .edit(entry))
                    } else {
                        Text(language.localized("Record not found", "Registro no encontrado"))
                    }
                }
            }
            .sheet(isPresented: $showingCreateTaskEditor) {
                NavigationStack {
                    LandTaskEditorView(mode: .create(land))
                }
            }
            .sheet(isPresented: $showingPairingAssistant) {
                NavigationStack {
                    DevicePairingAssistantView(
                        language: language,
                        measurementSystem: measurementSystem
                    ) { pairedDevice in
                        addPairedDevice(pairedDevice)
                    }
                }
            }
            .sheet(isPresented: $showingExpenseEditor) {
                ExpenseEditorView(land: land)
            }
            .sheet(isPresented: $showingEditTaskEditor, onDismiss: {
                editingTaskID = nil
            }) {
                NavigationStack {
                    if let task = editingTask {
                        LandTaskEditorView(mode: .edit(task))
                    } else {
                        Text(language.localized("Task not found", "Tarea no encontrada"))
                    }
                }
            }
            .sheet(isPresented: $showingDetailsSheet) {
                NavigationStack {
                    detailsSheetContent
                }
                .presentationDetents([.medium, .large])
            }
    }

    private var alertConfiguredContent: some View {
        sheetConfiguredContent
            .alert("Delete Land?", isPresented: $showingDelete) {
                Button("Delete", role: .destructive) {
                    let deletedID = land.id
                    context.delete(land)
                    try? context.save()
                    Task { @MainActor in
                        await SupabaseSyncService.shared.queueLandDelete(id: deletedID, context: context)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete this land.")
            }
            .alert(
                language.localized("Delete Record?", "¿Eliminar registro?"),
                isPresented: Binding(
                    get: { pendingDeleteHistoryEntry != nil },
                    set: { if !$0 { pendingDeleteHistoryEntry = nil } }
                )
            ) {
                Button(language.localized("Delete", "Eliminar"), role: .destructive) {
                    guard let entry = pendingDeleteHistoryEntry else { return }
                    deleteHistoryEntry(entry)
                    pendingDeleteHistoryEntry = nil
                }
                Button(language.localized("Cancel", "Cancelar"), role: .cancel) {
                    pendingDeleteHistoryEntry = nil
                }
            } message: {
                Text(language.localized("This action cannot be undone.", "Esta acción no se puede deshacer."))
            }
            .alert(
                language.localized("Delete Task?", "¿Eliminar tarea?"),
                isPresented: Binding(
                    get: { pendingDeleteTask != nil },
                    set: { if !$0 { pendingDeleteTask = nil } }
                )
            ) {
                Button(language.localized("Delete", "Eliminar"), role: .destructive) {
                    guard let task = pendingDeleteTask else { return }
                    deleteTask(task)
                    pendingDeleteTask = nil
                }
                Button(language.localized("Cancel", "Cancelar"), role: .cancel) {
                    pendingDeleteTask = nil
                }
            } message: {
                Text(language.localized("This action cannot be undone.", "Esta acción no se puede deshacer."))
            }
    }

    private var costsSectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(
                isExpanded: $isCostsExpanded,
                content: {
                    VStack(spacing: 12) {
                        financeHeroCard
                        timelineCard
                        expenseBreakdownCard
                    }
                    .padding(.top, 6)
                },
                label: {
                    SectionDisclosureLabel(
                        title: language.localized("Costs & Financials", "Costes y finanzas"),
                        systemImage: "eurosign.circle.fill",
                        tint: Color(red: 0.86, green: 0.46, blue: 0.12)
                    )
                }
            )
            .tint(Color(red: 0.86, green: 0.46, blue: 0.12))
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var operationsSectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(
                isExpanded: $isOperationsExpanded,
                content: {
                    VStack(spacing: 12) {
                        tasksCard
                        devicesCard

                        if canViewEconomics && ActivityCatalog.supportsEnergyMetrics(activityType: land.activityType) {
                            energyCard
                        }
                    }
                    .padding(.top, 6)
                },
                label: {
                    SectionDisclosureLabel(
                        title: supportsEnergyMetrics
                            ? language.localized("Field & Energy Operations", "Operación de campo y energía")
                            : language.localized("Field Operations", "Operación de campo"),
                        systemImage: "gearshape.2.fill",
                        tint: Color(red: 0.09, green: 0.41, blue: 0.77)
                    )
                }
            )
            .tint(Color(red: 0.09, green: 0.41, blue: 0.77))
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var mapCard: some View {
        ZStack {
            Map(initialPosition: .region(regionForLand(land))) {
                if !land.catastroRings.isEmpty {
                    ForEach(land.catastroRings.indices, id: \.self) { index in
                        let ring = land.catastroRings[index]
                        MapPolygon(coordinates: ring.map { $0.clLocation })
                            .foregroundStyle(mapAccentColor.opacity(0.22))
                            .stroke(mapAccentColor.opacity(0.9), lineWidth: 1.7)
                    }
                } else {
                    MapCircle(center: land.coordinate, radius: 90)
                        .foregroundStyle(mapAccentColor.opacity(0.2))
                        .stroke(mapAccentColor.opacity(0.9), lineWidth: 1.5)
                }
            }
            .frame(height: 225)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    private var projectLensCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: supportsEnergyMetrics ? "solarpanel" : "leaf.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(projectLensTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(projectLensSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ProjectSignalTile(
                    title: language.localized("Cadastre", "Catastro"),
                    value: hasCadastreFootprint ? language.localized("Ready", "Listo") : language.localized("Pending", "Pendiente"),
                    subtitle: hasCadastreFootprint
                        ? language.localized("Footprint imported", "Huella importada")
                        : language.localized("Import REFCAT or geometry", "Importa REFCAT o geometría"),
                    systemImage: "map.fill",
                    tint: Color(red: 0.16, green: 0.46, blue: 0.95)
                )

                ProjectSignalTile(
                    title: language.localized("Field Records", "Evidencia"),
                    value: "\(historyEntriesAscending.count)",
                    subtitle: hasOperationalHistory
                        ? language.localized("Historical entries", "Entradas históricas")
                        : language.localized("Create a baseline", "Crea una línea base"),
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: Color(red: 0.19, green: 0.66, blue: 0.40)
                )

                ProjectSignalTile(
                    title: language.localized("Sensors", "Sensores"),
                    value: "\(devices.count)",
                    subtitle: hasLinkedDevices
                        ? language.localized("Linked devices", "Dispositivos enlazados")
                        : language.localized("Optional validation layer", "Capa de validación opcional"),
                    systemImage: "dot.radiowaves.left.and.right",
                    tint: Color(red: 0.57, green: 0.46, blue: 0.92)
                )

                ProjectSignalTile(
                    title: language.localized("Energy Layer", "Capa energética"),
                    value: supportsEnergyMetrics
                        ? (hasEnergyConfiguration ? formattedCapacity : language.localized("Pending", "Pendiente"))
                        : language.localized("Off", "Desactivada"),
                    subtitle: supportsEnergyMetrics
                        ? (
                            hasEnergyConfiguration
                                ? language.localized("Capacity loaded", "Potencia cargada")
                                : language.localized("Waiting for project values", "Esperando valores de proyecto")
                        )
                        : language.localized("Enable via activity type", "Actívala desde la actividad"),
                    systemImage: "bolt.fill",
                    tint: Color(red: 0.86, green: 0.46, blue: 0.12)
                )
            }

            Text(projectLensFooter)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.31, blue: 0.58),
                    Color(red: 0.17, green: 0.53, blue: 0.39)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var financeHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.localized("Annual Net Margin", "Margen neto anual"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))

            Text(signedCurrency(land.annualNetMargin))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(netMarginColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 10) {
                FinanceStatTile(
                    title: language.localized("Income", "Ingresos"),
                    value: formattedIncome,
                    icon: "arrow.down.circle.fill",
                    tint: .green
                )
                FinanceStatTile(
                    title: language.localized("Expenses", "Gastos"),
                    value: formattedTotalExpenses,
                    icon: "arrow.up.circle.fill",
                    tint: .red
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(language.localized("Expense Ratio", "Ratio de gasto"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    Text(expenseRatioText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.92))
                }

                ProgressView(value: expenseRatioProgress)
                    .tint(Color(red: 0.95, green: 0.45, blue: 0.26))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.15),
                    Color(red: 0.12, green: 0.15, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.localized("Performance Timeline", "Evolución temporal"))
                    .font(.headline)
                Spacer()
                Button {
                    showingCreateHistoryEditor = true
                } label: {
                    Label(language.localized("Add", "Añadir"), systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            if historyEntriesAscending.isEmpty {
                Text(language.localized("Add monthly records to visualize trends of income, production and energy.", "Añade registros mensuales para visualizar tendencias de ingresos, producción y energía."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    language.localized("Metric", "Métrica"),
                    selection: $selectedTimelineMetric
                ) {
                    ForEach(TimelineMetric.allCases) { metric in
                        Text(metric.displayName(language: language)).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                Chart(chartEntries) { entry in
                    let value = selectedTimelineMetric.value(for: entry)

                    LineMark(
                        x: .value("Period", entry.periodDate),
                        y: .value(selectedTimelineMetric.displayName(language: language), value)
                    )
                    .foregroundStyle(selectedTimelineMetric.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Period", entry.periodDate),
                        y: .value(selectedTimelineMetric.displayName(language: language), value)
                    )
                    .foregroundStyle(selectedTimelineMetric.tint.opacity(0.15))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Period", entry.periodDate),
                        y: .value(selectedTimelineMetric.displayName(language: language), value)
                    )
                    .foregroundStyle(selectedTimelineMetric.tint)
                }
                .frame(height: 190)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(6, chartEntries.count))) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.22))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.defaultDigits))
                    }
                }

                Divider()

                VStack(spacing: 10) {
                    ForEach(historyEntriesDescending.prefix(6)) { entry in
                        HistoryEntryRow(
                            entry: entry,
                            currencyCode: currencyCode,
                            language: language,
                            isEditable: entry.source == .manual,
                            onEdit: {
                                editingHistoryEntryID = entry.id
                                showingEditHistoryEditor = true
                            },
                            onDelete: {
                                pendingDeleteHistoryEntry = entry
                            }
                        )
                    }
                }

                if historyEntriesDescending.count > 6 {
                    Text(language.localized("Showing latest 6 records", "Mostrando los últimos 6 registros"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                OperationCardHeader(
                    title: language.localized("Tasks & Reminders", "Tareas y recordatorios"),
                    systemImage: "calendar",
                    tint: Color(red: 0.08, green: 0.35, blue: 0.72)
                )
                Spacer()
                Button {
                    showingCreateTaskEditor = true
                } label: {
                    Label(language.localized("Add", "Añadir"), systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            TaskMiniCalendarView(
                scheduledDates: scheduledTaskDates,
                language: language
            )

            if tasksAscending.isEmpty {
                Text(
                    language.localized(
                        "Create tasks for irrigation, pruning, harvest and panel/inverter maintenance.",
                        "Crea tareas para riego, poda, cosecha y mantenimiento de paneles/inversores."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Picker(language.localized("Filter", "Filtro"), selection: $selectedTaskFilter) {
                    ForEach(LandTaskFilter.allCases) { filter in
                        Text(filter.displayName(language: language)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if filteredTasks.isEmpty {
                    Text(selectedTaskFilter.emptyState(language: language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredTasks) { task in
                            LandTaskRow(
                                task: task,
                                language: language,
                                isOverdue: isTaskOverdue(task),
                                onToggleComplete: {
                                    toggleTaskCompletion(task)
                                },
                                onEdit: {
                                    editingTaskID = task.id
                                    showingEditTaskEditor = true
                                },
                                onDelete: {
                                    pendingDeleteTask = task
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                OperationCardHeader(
                    title: language.localized("Installed Devices", "Dispositivos instalados"),
                    systemImage: "dot.radiowaves.left.and.right",
                    tint: .green
                )
                Spacer()
                if !devices.isEmpty {
                    Button {
                        Task { @MainActor in
                            await refreshLatestTelemetry(force: true)
                        }
                    } label: {
                        Image(systemName: isRefreshingTelemetry ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingTelemetry)
                    .accessibilityLabel(language.localized("Refresh telemetry", "Actualizar telemetría"))
                }
            }

            if let telemetryLastSyncAt {
                Text(
                    language.localized("Live sync", "Sincronización en vivo") +
                    ": " +
                    telemetryLastSyncAt.formatted(date: .omitted, time: .shortened)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if canManageStructure {
                Button {
                    showingPairingAssistant = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.localized("Pairing Assistant", "Asistente de enlazamiento"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(language.localized("Recommended for easy setup", "Recomendado para configuración fácil"))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                        }

                        Spacer()

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.07, green: 0.46, blue: 0.87),
                                Color(red: 0.12, green: 0.67, blue: 0.50)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                        if showingDeviceComposer {
                            showingDeviceComposer = false
                        } else {
                            deviceComposerStep = .type
                            showingDeviceComposer = true
                        }
                    }
                } label: {
                    Label(
                        showingDeviceComposer
                        ? language.localized("Hide form", "Ocultar formulario")
                        : language.localized("New Device", "Nuevo dispositivo"),
                        systemImage: showingDeviceComposer ? "xmark.circle.fill" : "plus.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(showingDeviceComposer ? Color.secondary : Color.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if showingDeviceComposer && canManageStructure {
                deviceComposerCard
                    .transition(.glassCardReveal)
            }

            if devices.isEmpty {
                Text(
                    language.localized(
                        "No devices registered yet. Add thermometers, water pumps, rain gauges and sensors.",
                        "Aún no hay dispositivos registrados. Añade termómetros, bombas de agua, pluviómetros y sensores."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(devices) { device in
                        LandDeviceRow(
                            device: device,
                            liveTelemetry: latestTelemetryByDeviceID[device.id],
                            language: language,
                            canDelete: canManageStructure,
                            onDelete: {
                                removeDevice(device)
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var deviceComposerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(value: deviceComposerProgress)
                .tint(deviceComposerAccentColor)

            HStack(spacing: 8) {
                ForEach(Array(deviceComposerSteps.enumerated()), id: \.element) { index, step in
                    Capsule()
                        .fill(index == deviceComposerStepIndex ? deviceComposerAccentColor : Color.primary.opacity(0.12))
                        .frame(width: index == deviceComposerStepIndex ? 30 : 10, height: 10)
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: deviceComposerStepIndex)
                        .accessibilityHidden(true)
                }

                Spacer()

                Text("\(deviceComposerStepIndex + 1)/\(deviceComposerSteps.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TabView(selection: $deviceComposerStep) {
                deviceComposerTypePage
                    .tag(DeviceComposerStep.type)

                deviceComposerLinkPage
                    .tag(DeviceComposerStep.link)

                if deviceLinkMethod == .bluetooth {
                    deviceComposerBluetoothPage
                        .tag(DeviceComposerStep.bluetooth)
                }

                deviceComposerSummaryPage
                    .tag(DeviceComposerStep.summary)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: deviceComposerPageHeight)

            HStack(spacing: 10) {
                Button(language.localized("Back", "Atrás")) {
                    moveDeviceComposer(by: -1)
                }
                .buttonStyle(.bordered)
                .opacity(deviceComposerStepIndex == 0 ? 0 : 1)
                .disabled(deviceComposerStepIndex == 0)

                Spacer()

                if isLastDeviceComposerStep {
                    Button {
                        addDevice()
                    } label: {
                        Label(language.localized("Add Device", "Añadir dispositivo"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAddDevice)
                } else {
                    Button(language.localized("Next", "Siguiente")) {
                        moveDeviceComposer(by: 1)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvanceFromCurrentDeviceComposerStep)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        )
    }

    private var deviceComposerAccentColor: Color {
        Color(uiColor: .systemGray2)
    }

    private var deviceComposerNamePage: some View {
        deviceComposerPage {
            DeviceFormField(
                label: language.localized("Device name", "Nombre del dispositivo"),
                placeholder: language.localized("Example: Main weather sensor", "Ejemplo: Sensor climático principal"),
                text: $deviceName,
                systemImage: deviceType.symbolName,
                tint: deviceTypeTint(deviceType)
            )
        }
    }

    private var deviceComposerTypePage: some View {
        deviceComposerPage {
            LazyVGrid(columns: deviceComposerGridColumns, spacing: 10) {
                ForEach(LandDeviceType.allCases) { type in
                    GlassSelectionCard(
                        title: type.displayName(language: language),
                        subtitle: deviceTypeDescription(type),
                        systemImage: type.symbolName,
                        tint: deviceTypeTint(type),
                        isSelected: deviceType == type
                    ) {
                        deviceType = type
                    }
                }
            }
        }
    }

    private var deviceComposerLinkPage: some View {
        deviceComposerPage {
            LazyVGrid(columns: deviceComposerGridColumns, spacing: 10) {
                ForEach(LandDeviceLinkMethod.allCases) { method in
                    GlassSelectionCard(
                        title: method.displayName(language: language),
                        subtitle: linkMethodDescription(method),
                        systemImage: method.symbolName,
                        tint: linkMethodTint(method),
                        isSelected: deviceLinkMethod == method
                    ) {
                        deviceLinkMethod = method
                    }
                }
            }
        }
    }

    private var deviceComposerBluetoothPage: some View {
        deviceComposerPage {
            BluetoothDeviceBrowserCard(
                language: language,
                pairingService: bluetoothPairingService
            )
        }
    }

    private var deviceComposerSummaryPage: some View {
        deviceComposerPage {
            VStack(spacing: 12) {
                DeviceFormField(
                    label: language.localized("Device name", "Nombre del dispositivo"),
                    placeholder: language.localized("Example: Main weather sensor", "Ejemplo: Sensor climático principal"),
                    text: $deviceName,
                    systemImage: deviceType.symbolName,
                    tint: deviceTypeTint(deviceType)
                )

                deviceComposerSummaryRow(
                    label: language.localized("Connection type", "Tipo de conexión"),
                    value: deviceLinkMethod.displayName(language: language),
                    systemImage: deviceLinkMethod.symbolName,
                    tint: linkMethodTint(deviceLinkMethod)
                )

                deviceComposerSummaryRow(
                    label: language.localized("Device type", "Tipo de dispositivo"),
                    value: deviceType.displayName(language: language),
                    systemImage: deviceType.symbolName,
                    tint: deviceTypeTint(deviceType)
                )
            }

            if !canAddDevice {
                Text(
                    deviceLinkMethod == .bluetooth
                    ? language.localized("The summary is ready, but one Bluetooth device still needs to be linked before adding it.", "El resumen ya está listo, pero todavía hay que enlazar un dispositivo Bluetooth antes de añadirlo.")
                    : language.localized("Complete the pending fields before adding the device.", "Completa los campos pendientes antes de añadir el dispositivo.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func deviceComposerPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 6)
    }

    @ViewBuilder
    private func deviceComposerSummaryRow(
        label: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func moveDeviceComposer(by value: Int) {
        guard let currentIndex = deviceComposerSteps.firstIndex(of: deviceComposerStep) else { return }
        let newIndex = min(max(0, currentIndex + value), deviceComposerSteps.count - 1)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            deviceComposerStep = deviceComposerSteps[newIndex]
        }
    }

    private var deviceComposerGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 155), spacing: 10)]
    }

    @ViewBuilder
    private func deviceComposerSection<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    private var expenseBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.localized("Expense Breakdown", "Desglose de gastos"))
                    .font(.headline)
                Spacer()
                if roleAccessViewModel.canManageExpenses {
                    Button {
                        showingExpenseEditor = true
                    } label: {
                        Label(language.localized("Update", "Actualizar"), systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }

            if land.annualTotalExpenses <= 0 {
                Text(language.localized("No expenses registered yet", "Aún no hay gastos registrados"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(expenseItems) { item in
                    ExpenseBarRow(
                        title: item.title,
                        amountText: item.amount.formatted(.currency(code: currencyCode)),
                        fraction: item.amount / max(land.annualTotalExpenses, 1),
                        tint: item.color
                    )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var energyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            OperationCardHeader(
                title: language.localized("Energy Layer", "Capa energética"),
                systemImage: "bolt.circle.fill",
                tint: .orange
            )

            FinanceDetailRow(label: language.localized("Installed Capacity", "Potencia instalada"), value: formattedCapacity)
            FinanceDetailRow(label: language.localized("Electricity Production", "Producción eléctrica"), value: formattedElectricity)
            FinanceDetailRow(label: language.localized("Self Consumption", "Autoconsumo"), value: formattedSelfConsumption)
            FinanceDetailRow(label: language.localized("Grid Export", "Vertido a red"), value: formattedGridExport)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var detailsFloatingButton: some View {
        Button {
            showingDetailsSheet = true
        } label: {
            Label(language.localized("Project Info", "Ficha"), systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(.primary)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.bottom, 18)
    }

    private var detailsSheetContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(language.localized("Project Profile", "Perfil del proyecto"))
                        .font(.headline)

                    FinanceDetailRow(label: language.localized("Activity", "Actividad"), value: localizedActivityType)
                    FinanceDetailRow(label: language.localized("Production", "Producción"), value: localizedProductionType)
                    FinanceDetailRow(
                        label: language.localized("Subtype", "Subtipo"),
                        value: localizedSubtypeOrDash == "-" ? language.localized("Not set", "Sin definir") : localizedSubtypeOrDash
                    )
                    FinanceDetailRow(
                        label: language.localized("Group", "Grupo"),
                        value: land.group?.name ?? language.localized("Ungrouped", "Sin grupo")
                    )
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text(language.localized("Project Context", "Contexto del proyecto"))
                        .font(.headline)

                    FinanceDetailRow(label: language.localized("Size", "Superficie"), value: formattedSize)
                    FinanceDetailRow(label: language.localized("Location", "Ubicación"), value: land.locationText)
                    FinanceDetailRow(label: language.localized("Created", "Creado"), value: formattedCreatedAt)
                    FinanceDetailRow(label: language.localized("Last Updated", "Última actualización"), value: formattedUpdatedAt)
                    FinanceDetailRow(label: language.localized("Tasks", "Tareas"), value: "\(tasksAscending.count)")
                    FinanceDetailRow(label: language.localized("Devices", "Dispositivos"), value: "\(devices.count)")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if hasCadastreInfo {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(language.localized("Project Geometry", "Geometría del proyecto"))
                            .font(.headline)

                        if let refcat = land.catastroRefcat14 {
                            FinanceDetailRow(label: "REFCAT", value: refcat)
                        }
                        if let areaValue = land.catastroAreaValue {
                            let uom = land.catastroAreaUom ?? "m²"
                            FinanceDetailRow(
                                label: language.localized("Cadastre Area", "Superficie catastral"),
                                value: "\(areaValue.formatted(.number.precision(.fractionLength(2)))) \(uom)"
                            )
                        }
                        if let label = land.catastroLabel {
                            FinanceDetailRow(label: language.localized("Cadastre Label", "Etiqueta catastral"), value: label)
                        }
                        if let fetchedAt = land.catastroFetchedAt {
                            FinanceDetailRow(
                                label: language.localized("Synced", "Sincronizado"),
                                value: fetchedAt.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(language.localized("Project Details", "Detalles del proyecto"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(language.localized("Done", "Cerrar")) {
                    showingDetailsSheet = false
                }
            }
        }
    }

    private var hasCadastreInfo: Bool {
        land.catastroRefcat14 != nil ||
        land.catastroAreaValue != nil ||
        land.catastroLabel != nil ||
        land.catastroFetchedAt != nil
    }

    private var hasOperationalHistory: Bool {
        !historyEntriesAscending.isEmpty
    }

    private var hasLinkedDevices: Bool {
        !devices.isEmpty
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.localized("Project Notes", "Notas del proyecto"))
                .font(.headline)
            Text(land.notes)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var formattedIncome: String {
        land.incomeAnnual.formatted(.currency(code: currencyCode))
    }

    private var formattedTotalExpenses: String {
        land.annualTotalExpenses.formatted(.currency(code: currencyCode))
    }

    private var formattedSize: String {
        AppSettings.formatArea(
            acres: land.sizeAcres,
            system: measurementSystem,
            language: language,
            fractionDigits: 2
        )
    }

    private var formattedCapacity: String {
        "\(land.installedCapacityKW.formatted(.number.precision(.fractionLength(2)))) kW"
    }

    private var formattedElectricity: String {
        "\(land.annualElectricityProductionKWh.formatted(.number.precision(.fractionLength(2)))) kWh/year"
    }

    private var formattedSelfConsumption: String {
        "\(land.selfConsumptionRate.formatted(.number.precision(.fractionLength(2))))%"
    }

    private var formattedGridExport: String {
        "\(land.gridExportRate.formatted(.number.precision(.fractionLength(2))))%"
    }

    private var formattedUpdatedAt: String {
        land.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var formattedCreatedAt: String {
        land.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func signedCurrency(_ value: Double) -> String {
        let amount = abs(value).formatted(.currency(code: currencyCode))
        if value > 0 {
            return "+\(amount)"
        }
        if value < 0 {
            return "-\(amount)"
        }
        return amount
    }

    private func deleteHistoryEntry(_ entry: LandHistoryEntry) {
        let deletedID = entry.id
        let shouldSyncDelete = entry.source == .manual
        context.delete(entry)
        land.touchUpdatedAt()
        try? context.save()
        Task { @MainActor in
            if shouldSyncDelete {
                await SupabaseSyncService.shared.queueHistoryEntryDelete(id: deletedID, context: context)
            }
            await SupabaseSyncService.shared.queueLandUpsert(id: land.id, context: context)
        }
    }

    private func isTaskOverdue(_ task: LandTask) -> Bool {
        !task.isCompleted && task.dueDate < Date()
    }

    private func toggleTaskCompletion(_ task: LandTask) {
        if task.isCompleted {
            task.reopen()
        } else {
            task.markCompleted()
        }
        land.touchUpdatedAt()
        try? context.save()

        Task { @MainActor in
            if task.isCompleted {
                TaskReminderService.shared.cancelReminder(taskID: task.id)
            } else {
                await TaskReminderService.shared.upsertReminder(for: task, landName: land.name, language: language)
            }
            await SupabaseSyncService.shared.queueTaskUpsert(id: task.id, context: context)
            await SupabaseSyncService.shared.queueLandUpsert(id: land.id, context: context)
        }
    }

    private func deleteTask(_ task: LandTask) {
        let taskID = task.id
        context.delete(task)
        land.touchUpdatedAt()
        try? context.save()

        Task { @MainActor in
            TaskReminderService.shared.cancelReminder(taskID: taskID)
            await SupabaseSyncService.shared.queueTaskDelete(id: taskID, context: context)
            await SupabaseSyncService.shared.queueLandUpsert(id: land.id, context: context)
        }
    }

    private func defaultMetric(for type: LandDeviceType) -> (name: String, unit: String) {
        switch type {
        case .thermometer:
            return (
                language.localized("Temperature", "Temperatura"),
                measurementSystem == .imperial ? "F" : "C"
            )
        case .waterPump:
            return (
                language.localized("Flow", "Caudal"),
                measurementSystem == .imperial ? "gal/min" : "L/min"
            )
        case .rainGauge:
            return (
                language.localized("Rain", "Lluvia"),
                measurementSystem == .imperial ? "in" : "mm"
            )
        case .humiditySensor:
            return (language.localized("Humidity", "Humedad"), "%")
        case .pressureSensor:
            return (
                language.localized("Pressure", "Presión"),
                measurementSystem == .imperial ? "psi" : "hPa"
            )
        case .energyMeter:
            return (language.localized("Energy", "Energía"), "kWh")
        case .inverter:
            return (language.localized("Power", "Potencia"), "kW")
        case .other:
            return (language.localized("Value", "Valor"), "")
        }
    }

    private func addDevice() {
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let linkedBluetoothDevice = deviceLinkMethod == .bluetooth ? bluetoothPairingService.connectedDevice : nil
        guard deviceLinkMethod != .bluetooth || linkedBluetoothDevice != nil else { return }

        let metricDefaults = defaultMetric(for: deviceType)
        let intervalMinutes = 5
        let normalizedIntervalSeconds = IoTDeviceLinkService.shared.normalizedIntervalSeconds(
            requestedMinutes: intervalMinutes,
            method: deviceLinkMethod
        )
        let latestSample = deviceLinkMethod == .bluetooth ? bluetoothPairingService.latestSample : nil

        let device = LandDevice(
            name: trimmedName,
            type: deviceType,
            manufacturer: deviceManufacturerTitle(for: deviceLinkMethod),
            model: deviceLinkMethod == .bluetooth ? (linkedBluetoothDevice?.name ?? "") : "",
            serialNumber: deviceLinkMethod == .bluetooth ? (linkedBluetoothDevice?.id.uuidString ?? "") : "",
            metricName: metricDefaults.name,
            metricUnit: metricDefaults.unit,
            lastReadingValue: latestSample?.valueDouble,
            lastSeenAt: latestSample?.observedAt,
            notes: deviceNotes(
                for: deviceLinkMethod,
                linkedName: linkedBluetoothDevice?.name,
                sample: latestSample
            ),
            linkMethod: deviceLinkMethod,
            linkState: deviceLinkMethod == .manual ? .unlinked : .linked,
            telemetryIntervalSeconds: normalizedIntervalSeconds
        )

        var updatedDevices = land.devices
        updatedDevices.append(device)
        land.devices = updatedDevices
        land.touchUpdatedAt()
        try? context.save()

        Task { @MainActor in
            await SupabaseSyncService.shared.queueLandUpsert(id: land.id, context: context)
            _ = try? await SupabaseIoTService.shared.registerDevice(device, landID: land.id)
            _ = try? await SupabaseIoTService.shared.pushSnapshotTelemetry(for: device)
        }

        resetDeviceForm()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            showingDeviceComposer = false
        }
    }

    private func addPairedDevice(_ device: LandDevice) {
        var updatedDevices = land.devices
        let normalizedSerial = device.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let deviceToSync: LandDevice

        if
            !normalizedSerial.isEmpty,
            let existingIndex = updatedDevices.firstIndex(where: {
                $0.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedSerial
            })
        {
            var merged = device
            merged.id = updatedDevices[existingIndex].id
            updatedDevices[existingIndex] = merged
            deviceToSync = merged
        } else {
            updatedDevices.append(device)
            deviceToSync = device
        }

        land.devices = updatedDevices
        land.touchUpdatedAt()
        try? context.save()

        Task { @MainActor in
            await SupabaseSyncService.shared.queueLandUpsert(id: land.id, context: context)
            _ = try? await SupabaseIoTService.shared.registerDevice(deviceToSync, landID: land.id)
            _ = try? await SupabaseIoTService.shared.pushSnapshotTelemetry(for: deviceToSync)
            await refreshLatestTelemetry(force: true)
        }

    }

    private func removeDevice(_ device: LandDevice) {
        var updatedDevices = land.devices
        updatedDevices.removeAll { $0.id == device.id }
        land.devices = updatedDevices
        land.touchUpdatedAt()
        try? context.save()

        Task { @MainActor in
            await SupabaseSyncService.shared.queueLandUpsert(id: land.id, context: context)
            try? await SupabaseIoTService.shared.removeDevice(deviceID: device.id)
        }
    }

    private func resetDeviceForm() {
        deviceName = ""
        deviceType = .thermometer
        deviceLinkMethod = .bluetooth
        deviceComposerStep = .type
        bluetoothPairingService.resetSession()
    }

    private func syncDeviceComposerStepForCurrentMethod() {
        guard !deviceComposerSteps.contains(deviceComposerStep) else { return }
        deviceComposerStep = .summary
    }

    private func startBluetoothScanIfNeeded() {
        guard showingDeviceComposer, deviceLinkMethod == .bluetooth else { return }
        guard bluetoothPairingService.connectedDevice == nil else { return }
        guard bluetoothPairingService.isBluetoothReady, !bluetoothPairingService.isScanning else { return }
        bluetoothPairingService.startScanning()
    }

    private func deviceManufacturerTitle(for method: LandDeviceLinkMethod) -> String {
        switch method {
        case .bluetooth:
            return "Bluetooth"
        case .cloudAPI:
            return "Cloud API"
        case .mqttGateway:
            return "MQTT Gateway"
        case .manual:
            return "Manual"
        }
    }

    private func deviceNotes(
        for method: LandDeviceLinkMethod,
        linkedName: String?,
        sample: BluetoothDataSample?
    ) -> String {
        switch method {
        case .bluetooth:
            if let linkedName, let sample {
                return language.localized(
                    "Linked from direct form using Bluetooth (\(linkedName)). Initial sample: \(sample.displayValue).",
                    "Enlazado desde el formulario directo por Bluetooth (\(linkedName)). Muestra inicial: \(sample.displayValue)."
                )
            }
            if let linkedName {
                return language.localized(
                    "Linked from direct form using Bluetooth (\(linkedName)).",
                    "Enlazado desde el formulario directo por Bluetooth (\(linkedName))."
                )
            }
            return language.localized(
                "Linked from direct form using Bluetooth.",
                "Enlazado desde el formulario directo por Bluetooth."
            )
        case .cloudAPI:
            return language.localized(
                "Configured from direct form for cloud ingestion.",
                "Configurado desde el formulario directo para ingesta en la nube."
            )
        case .mqttGateway:
            return language.localized(
                "Configured from direct form for gateway ingestion.",
                "Configurado desde el formulario directo para ingesta por pasarela."
            )
        case .manual:
            return language.localized(
                "Created from direct form. Pending physical link.",
                "Creado desde el formulario directo. Pendiente de enlace físico."
            )
        }
    }

    @MainActor
    private func refreshLatestTelemetry(force: Bool = false) async {
        guard !devices.isEmpty else {
            latestTelemetryByDeviceID = [:]
            telemetryLastSyncAt = nil
            return
        }

        if isRefreshingTelemetry && !force {
            return
        }

        isRefreshingTelemetry = true
        defer { isRefreshingTelemetry = false }

        var freshTelemetry: [UUID: IoTTelemetryRecord] = [:]

        for device in devices where device.isActive {
            if let record = try? await SupabaseIoTService.shared
                .fetchRecentTelemetry(deviceID: device.id, limit: 1)
                .first {
                freshTelemetry[device.id] = record
            }
        }

        latestTelemetryByDeviceID = freshTelemetry
        telemetryLastSyncAt = Date()
    }

    @MainActor
    private func backfillIoTDevicesIfNeeded() async {
        guard canManageStructure else { return }
        let snapshot = land.devices
        guard !snapshot.isEmpty else { return }
        try? await SupabaseIoTService.shared.syncDevices(snapshot, landID: land.id)
    }

    private func regionForLand(_ land: Land) -> MKCoordinateRegion {
        if let region = regionForRings(land.catastroRings) {
            return region
        }
        return MKCoordinateRegion(
            center: land.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    }

    private func regionForRings(_ rings: [[Coordinate]]) -> MKCoordinateRegion? {
        let coords = rings.flatMap { $0 }
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
}

private enum TimelineMetric: String, CaseIterable, Identifiable {
    case income
    case production
    case electricity

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .income:
            return language.localized("Income", "Ingresos")
        case .production:
            return language.localized("Production", "Producción")
        case .electricity:
            return language.localized("Electricity", "Electricidad")
        }
    }

    func value(for entry: LandHistoryEntry) -> Double {
        switch self {
        case .income:
            return entry.incomeAmount
        case .production:
            return entry.productionAmount
        case .electricity:
            return entry.electricityKWh
        }
    }

    var tint: Color {
        switch self {
        case .income:
            return .green
        case .production:
            return .orange
        case .electricity:
            return .blue
        }
    }
}

private enum LandTaskFilter: String, CaseIterable, Identifiable {
    case pending
    case overdue
    case completed
    case all

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .pending:
            return language.localized("Pending", "Pendientes")
        case .overdue:
            return language.localized("Overdue", "Vencidas")
        case .completed:
            return language.localized("Done", "Completadas")
        case .all:
            return language.localized("All", "Todas")
        }
    }

    func emptyState(language: AppLanguage) -> String {
        switch self {
        case .pending:
            return language.localized("No pending tasks.", "No hay tareas pendientes.")
        case .overdue:
            return language.localized("No overdue tasks.", "No hay tareas vencidas.")
        case .completed:
            return language.localized("No completed tasks yet.", "Aún no hay tareas completadas.")
        case .all:
            return language.localized("No tasks yet.", "Aún no hay tareas.")
        }
    }

    func matches(task: LandTask, now: Date) -> Bool {
        switch self {
        case .pending:
            return !task.isCompleted
        case .overdue:
            return !task.isCompleted && task.dueDate < now
        case .completed:
            return task.isCompleted
        case .all:
            return true
        }
    }
}

private struct ExpenseItem: Identifiable {
    let id: String
    let title: String
    let amount: Double
    let color: Color
}

private struct LandTaskRow: View {
    let task: LandTask
    let language: AppLanguage
    let isOverdue: Bool
    let onToggleComplete: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var dueDateText: String {
        task.dueDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var reminderText: String? {
        guard let reminderDate = task.reminderDate else { return nil }
        return reminderDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var notesText: String {
        task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var dueColor: Color {
        if task.isCompleted {
            return .secondary
        }
        return isOverdue ? .red : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onToggleComplete) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(task.isCompleted, color: .secondary)

                    HStack(spacing: 8) {
                        Label(task.type.displayName(language: language), systemImage: task.type.symbolName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08), in: Capsule())

                        Label(dueDateText, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(dueColor)
                    }

                    if let reminderText {
                        Label(reminderText, systemImage: "bell")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Menu {
                    Button(language.localized("Edit", "Editar"), action: onEdit)
                    Button(language.localized("Delete", "Eliminar"), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            if !notesText.isEmpty {
                Text(notesText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TaskMiniCalendarView: View {
    let scheduledDates: [Date]
    let language: AppLanguage

    @State private var visibleMonth = Date()

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = language == .spanish ? Locale(identifier: "es_ES") : Locale(identifier: "en_US")
        value.firstWeekday = language == .spanish ? 2 : 1
        return value
    }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)) ?? visibleMonth
    }

    private var weekdaySymbols: [String] {
        let base = calendar.veryShortStandaloneWeekdaySymbols
        let shift = max(0, min(6, calendar.firstWeekday - 1))
        return (0..<7).map { base[($0 + shift) % 7] }
    }

    private var monthGrid: [Date?] {
        guard let daysRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingPadding = (firstWeekday - calendar.firstWeekday + 7) % 7

        var values: [Date?] = Array(repeating: nil, count: leadingPadding)
        for day in daysRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                values.append(date)
            }
        }

        let trailingPadding = (7 - (values.count % 7)) % 7
        if trailingPadding > 0 {
            values.append(contentsOf: Array(repeating: nil, count: trailingPadding))
        }

        return values
    }

    private var eventsByDay: [Date: Int] {
        var bucket: [Date: Int] = [:]
        for date in scheduledDates {
            let day = calendar.startOfDay(for: date)
            bucket[day, default: 0] += 1
        }
        return bucket
    }

    private var scheduledCountInMonth: Int {
        eventsByDay.reduce(into: 0) { partialResult, element in
            if calendar.isDate(element.key, equalTo: monthStart, toGranularity: .month) {
                partialResult += element.value
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text(
                    visibleMonth.formatted(
                        Date.FormatStyle()
                            .locale(calendar.locale ?? Locale.current)
                            .month(.wide)
                            .year()
                    )
                )
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 18)
                }

                ForEach(Array(monthGrid.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear
                            .frame(height: 34)
                    }
                }
            }

            Text(
                scheduledCountInMonth > 0
                ? language.localized(
                    "\(scheduledCountInMonth) scheduled item(s) this month",
                    "\(scheduledCountInMonth) elemento(s) programado(s) este mes"
                )
                : language.localized(
                    "No scheduled items this month",
                    "No hay elementos programados este mes"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let key = calendar.startOfDay(for: date)
        let isToday = calendar.isDateInToday(date)
        let hasEvent = (eventsByDay[key] ?? 0) > 0
        let todayBlue = Color(red: 0.08, green: 0.35, blue: 0.72)

        ZStack {
            if isToday {
                Circle()
                    .fill(todayBlue)
                    .frame(width: 30, height: 30)
            } else if hasEvent {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 30, height: 30)
            } else {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 30, height: 30)
            }

            Text("\(day)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isToday ? .white : (hasEvent ? Color.accentColor : Color.primary))

            if hasEvent {
                VStack {
                    Spacer()
                    Circle()
                        .fill(isToday ? Color.white.opacity(0.95) : Color.accentColor)
                        .frame(width: 4, height: 4)
                        .padding(.bottom, 1)
                }
            }
        }
        .frame(width: 34, height: 34, alignment: .center)
    }

    private func shiftMonth(by value: Int) {
        if let newValue = calendar.date(byAdding: .month, value: value, to: visibleMonth) {
            visibleMonth = newValue
        }
    }
}

private struct LandDeviceRow: View {
    let device: LandDevice
    let liveTelemetry: IoTTelemetryRecord?
    let language: AppLanguage
    let canDelete: Bool
    let onDelete: () -> Void

    private var typeLabel: String {
        device.type.displayName(language: language)
    }

    private var installedText: String {
        device.installedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var lastSeenText: String? {
        if let observedAt = liveTelemetry?.observedAt {
            return observedAt.formatted(date: .abbreviated, time: .shortened)
        }
        guard let lastSeenAt = device.lastSeenAt else { return nil }
        return lastSeenAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var readingText: String? {
        guard let value = liveTelemetry?.valueDouble ?? device.lastReadingValue else { return nil }
        let formatted = value.formatted(.number.precision(.fractionLength(2)))
        let liveUnit = (liveTelemetry?.metricUnit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackUnit = device.metricUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = liveUnit.isEmpty ? fallbackUnit : liveUnit
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }

    private var linkMethodText: String {
        device.linkMethod.displayName(language: language)
    }

    private var intervalText: String {
        language.localized("Every", "Cada") + " \(device.telemetryIntervalMinutes) min"
    }

    private var trimmedNotes: String {
        device.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: device.type.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(device.isActive ? Color.accentColor : .secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        Label(typeLabel, systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08), in: Capsule())

                        Label(
                            device.isActive
                            ? language.localized("Active", "Activo")
                            : language.localized("Inactive", "Inactivo"),
                            systemImage: device.isActive ? "checkmark.circle.fill" : "pause.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(device.isActive ? .green : .secondary)
                    }

                    HStack(spacing: 8) {
                        Label(linkMethodText, systemImage: device.linkMethod.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(intervalText, systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let readingText {
                        Label(readingText, systemImage: "waveform.path.ecg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Label(installedText, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastSeenText {
                        Label(lastSeenText, systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if canDelete {
                    Menu {
                        Button(language.localized("Delete", "Eliminar"), role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !trimmedNotes.isEmpty {
                Text(trimmedNotes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OperationCardHeader: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(title)
                .font(.headline)
        }
    }
}

private struct SectionDisclosureLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
        }
    }
}

private struct DeviceFormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let systemImage: String
    let tint: Color
    var keyboardType: UIKeyboardType = .default

    private var isFilled: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFilled ? .white : tint)
                    .frame(width: 32, height: 32)
                    .background(
                        isFilled ? tint : tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )

                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)

                if isFilled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isFilled ? tint.opacity(0.4) : Color.primary.opacity(0.12),
                        lineWidth: 1
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isFilled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GlassCardModifier: ViewModifier {
    let opacity: Double
    let blur: CGFloat
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blur)
            .scaleEffect(scale)
    }
}

private extension AnyTransition {
    static var glassCardReveal: AnyTransition {
        .modifier(
            active: GlassCardModifier(opacity: 0, blur: 10, scale: 0.98),
            identity: GlassCardModifier(opacity: 1, blur: 0, scale: 1)
        )
    }
}

private struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct ProjectSignalTile: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct FinanceStatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ExpenseBarRow: View {
    let title: String
    let amountText: String
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(amountText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let width = max(0, min(1, fraction)) * geometry.size.width

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: width)
                }
            }
            .frame(height: 8)
        }
    }
}

private struct FinanceDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct HistoryEntryRow: View {
    let entry: LandHistoryEntry
    let currencyCode: String
    let language: AppLanguage
    let isEditable: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var periodText: String {
        entry.periodDate.formatted(.dateTime.month(.wide).year(.defaultDigits))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(periodText.capitalized)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isEditable {
                    HStack(spacing: 6) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    Text("Excel")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 10) {
                MetricPill(
                    title: language.localized("Income", "Ingresos"),
                    value: entry.incomeAmount.formatted(.currency(code: currencyCode)),
                    tint: .green
                )
                MetricPill(
                    title: language.localized("Production", "Producción"),
                    value: "\(entry.productionAmount.formatted(.number.precision(.fractionLength(2)))) \(entry.productionUnit)",
                    tint: .orange
                )
                MetricPill(
                    title: language.localized("Electricity", "Electricidad"),
                    value: "\(entry.electricityKWh.formatted(.number.precision(.fractionLength(0)))) kWh",
                    tint: .blue
                )
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
