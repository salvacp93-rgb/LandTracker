import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel
    @Query(sort: \Land.name) private var lands: [Land]
    @Query(sort: \LandGroup.name) private var groups: [LandGroup]
    @Query private var tasks: [LandTask]
    @Query private var historyEntries: [LandHistoryEntry]
    @Query(sort: \PendingSyncOperation.createdAt) private var pendingOperations: [PendingSyncOperation]
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @AppStorage(AccountPreferences.measurementSystemKey) private var measurementSystemRaw = AppSettings.defaultMeasurementSystem.rawValue
    @AppStorage(AccountPreferences.preferredCurrencyCodeKey) private var preferredCurrencyCode = AppSettings.defaultCurrency.rawValue
    @State private var showingAccount = false
    @State private var showingSettings = false
    @State private var showingCreateLand = false
    @State private var showingCreateGroup = false
    @State private var showingTeam = false

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var measurementSystem: AppMeasurementSystem {
        AppSettings.measurementSystem(from: measurementSystemRaw)
    }

    private var currencyCode: String {
        AppSettings.currencyCode(from: preferredCurrencyCode)
    }

    private var calendar: Calendar {
        .current
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

    private var endOfToday: Date {
        calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
    }

    private var sixHoursAgo: Date {
        Date().addingTimeInterval(-6 * 60 * 60)
    }

    private var pendingTasks: [LandTask] {
        tasks
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                if lhs.dueDate == rhs.dueDate {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.dueDate < rhs.dueDate
            }
    }

    private var overdueTasks: [LandTask] {
        pendingTasks.filter { $0.dueDate < startOfToday }
    }

    private var dueTodayTasks: [LandTask] {
        pendingTasks.filter { $0.dueDate >= startOfToday && $0.dueDate < endOfToday }
    }

    private var upcomingTasks: [LandTask] {
        Array(pendingTasks.prefix(5))
    }

    private var ungroupedLandCount: Int {
        lands.filter { $0.group == nil }.count
    }

    private var totalAreaAcres: Double {
        lands.reduce(0) { $0 + max(0, $1.sizeAcres) }
    }

    private var totalIncome: Double {
        lands.reduce(0) { $0 + max(0, $1.incomeAnnual) }
    }

    private var totalExpenses: Double {
        lands.reduce(0) { $0 + $1.annualTotalExpenses }
    }

    private var totalNetMargin: Double {
        totalIncome - totalExpenses
    }

    private var totalInstalledCapacityKW: Double {
        lands.reduce(0) { $0 + max(0, $1.installedCapacityKW) }
    }

    private var totalAnnualElectricityKWh: Double {
        lands.reduce(0) { $0 + max(0, $1.annualElectricityProductionKWh) }
    }

    private var hasEnergyLands: Bool {
        lands.contains { ActivityCatalog.supportsEnergyMetrics(activityType: $0.activityType) }
    }

    private var agrovoltaicLandCount: Int {
        lands.filter {
            ActivityCatalog.item(for: $0.activityType)?.name == ActivityCatalog.agrovoltaic
        }.count
    }

    private var landsWithCadastreCount: Int {
        lands.filter { hasCadastreData(for: $0) }.count
    }

    private var landsWithHistoryCount: Int {
        lands.filter { !$0.historyEntries.isEmpty }.count
    }

    private var monitoredLandCount: Int {
        lands.filter { !$0.devices.isEmpty }.count
    }

    private var dualUseReadyLandCount: Int {
        lands.filter { dualUseReadinessScore(for: $0) >= 3 }.count
    }

    private var allDevices: [(land: Land, device: LandDevice)] {
        lands.flatMap { land in
            land.devices.map { (land: land, device: $0) }
        }
    }

    private var totalDeviceCount: Int {
        allDevices.count
    }

    private var activeDeviceCount: Int {
        allDevices.filter { $0.device.isActive }.count
    }

    private var offlineDeviceCount: Int {
        allDevices.filter { $0.device.isActive && isDeviceOffline($0.device) }.count
    }

    private var lowBatteryDeviceCount: Int {
        allDevices.filter { $0.device.isActive && isLowBattery($0.device) }.count
    }

    private var onlineDeviceCount: Int {
        max(0, activeDeviceCount - offlineDeviceCount)
    }

    private var pendingSyncCount: Int {
        pendingOperations.count
    }

    private var syncErrorCount: Int {
        pendingOperations.filter { $0.lastError != nil }.count
    }

    private var overviewMetrics: [DashboardMetricItem] {
        if roleAccessViewModel.canViewEconomics {
            var items: [DashboardMetricItem] = [
                DashboardMetricItem(
                    id: "groups",
                    title: language.localized("Groups", "Grupos"),
                    value: "\(groups.count)",
                    subtitle: language.localized("Structure buckets", "Estructura creada"),
                    tint: Color(red: 0.19, green: 0.66, blue: 0.40)
                ),
                DashboardMetricItem(
                    id: "area",
                    title: language.localized("Area", "Superficie"),
                    value: "\(AppSettings.areaValue(fromAcres: totalAreaAcres, system: measurementSystem).formatted(.number.precision(.fractionLength(1)))) \(AppSettings.areaShortUnit(system: measurementSystem))",
                    subtitle: language.localized("Across all lands", "En todos los terrenos"),
                    tint: Color(red: 0.12, green: 0.43, blue: 0.86)
                ),
                DashboardMetricItem(
                    id: "income",
                    title: language.localized("Income", "Ingresos"),
                    value: totalIncome.formatted(.currency(code: currencyCode)),
                    subtitle: language.localized("Annual total", "Total anual"),
                    tint: Color(red: 0.08, green: 0.62, blue: 0.47)
                ),
                DashboardMetricItem(
                    id: "margin",
                    title: language.localized("Net Margin", "Margen neto"),
                    value: totalNetMargin.formatted(.currency(code: currencyCode)),
                    subtitle: language.localized("Income minus expenses", "Ingresos menos gastos"),
                    tint: totalNetMargin >= 0
                        ? Color(red: 0.10, green: 0.58, blue: 0.38)
                        : Color(red: 0.83, green: 0.24, blue: 0.27)
                ),
                DashboardMetricItem(
                    id: "devices",
                    title: language.localized("Devices", "Dispositivos"),
                    value: "\(totalDeviceCount)",
                    subtitle: totalDeviceCount == 0
                        ? language.localized("No devices linked", "Sin dispositivos enlazados")
                        : language.localized("\(onlineDeviceCount) online", "\(onlineDeviceCount) en línea"),
                    tint: Color(red: 0.16, green: 0.67, blue: 0.58)
                )
            ]

            if hasEnergyLands {
                items.append(
                    DashboardMetricItem(
                        id: "energy",
                        title: language.localized("Installed kW", "kW instalados"),
                        value: "\(totalInstalledCapacityKW.formatted(.number.precision(.fractionLength(1)))) kW",
                        subtitle: language.localized("Annual energy tracked", "Con energía anual registrada"),
                        tint: Color(red: 0.96, green: 0.66, blue: 0.18)
                    )
                )
            } else {
                items.append(
                    DashboardMetricItem(
                        id: "pending_tasks",
                        title: language.localized("Pending Tasks", "Tareas pendientes"),
                        value: "\(pendingTasks.count)",
                        subtitle: overdueTasks.isEmpty
                            ? language.localized("No overdue items", "Sin tareas vencidas")
                            : language.localized("\(overdueTasks.count) overdue", "\(overdueTasks.count) vencidas"),
                        tint: overdueTasks.isEmpty
                            ? Color(red: 0.12, green: 0.43, blue: 0.86)
                            : Color(red: 0.91, green: 0.45, blue: 0.20)
                    )
                )
            }

            return items
        }

        return [
            DashboardMetricItem(
                id: "groups",
                title: language.localized("Groups", "Grupos"),
                value: "\(groups.count)",
                subtitle: language.localized("Structure buckets", "Estructura creada"),
                tint: Color(red: 0.19, green: 0.66, blue: 0.40)
            ),
            DashboardMetricItem(
                id: "area",
                title: language.localized("Area", "Superficie"),
                value: "\(AppSettings.areaValue(fromAcres: totalAreaAcres, system: measurementSystem).formatted(.number.precision(.fractionLength(1)))) \(AppSettings.areaShortUnit(system: measurementSystem))",
                subtitle: language.localized("Across all lands", "En todos los terrenos"),
                tint: Color(red: 0.12, green: 0.43, blue: 0.86)
            ),
            DashboardMetricItem(
                id: "pending_tasks",
                title: language.localized("Pending Tasks", "Tareas pendientes"),
                value: "\(pendingTasks.count)",
                subtitle: language.localized("Ordered by due date", "Ordenadas por vencimiento"),
                tint: Color(red: 0.16, green: 0.46, blue: 0.95)
            ),
            DashboardMetricItem(
                id: "overdue",
                title: language.localized("Overdue", "Vencidas"),
                value: "\(overdueTasks.count)",
                subtitle: language.localized("Need action first", "Atiéndelas primero"),
                tint: overdueTasks.isEmpty
                    ? Color(red: 0.16, green: 0.67, blue: 0.58)
                    : Color(red: 0.91, green: 0.45, blue: 0.20)
            ),
            DashboardMetricItem(
                id: "devices",
                title: language.localized("Devices", "Dispositivos"),
                value: "\(totalDeviceCount)",
                subtitle: totalDeviceCount == 0
                    ? language.localized("No devices linked", "Sin dispositivos enlazados")
                    : language.localized("\(onlineDeviceCount) online", "\(onlineDeviceCount) en línea"),
                tint: Color(red: 0.16, green: 0.67, blue: 0.58)
            ),
            DashboardMetricItem(
                id: "sync",
                title: language.localized("Sync", "Sincronización"),
                value: pendingSyncCount == 0
                    ? language.localized("Ready", "Lista")
                    : "\(pendingSyncCount)",
                subtitle: syncErrorCount == 0
                    ? language.localized("Cloud queue healthy", "Cola en buen estado")
                    : language.localized("\(syncErrorCount) issues", "\(syncErrorCount) incidencias"),
                tint: syncErrorCount == 0
                    ? Color(red: 0.57, green: 0.46, blue: 0.92)
                    : Color(red: 0.83, green: 0.24, blue: 0.27)
            )
        ]
    }

    private var attentionAlerts: [DashboardAlertItem] {
        var items: [DashboardAlertItem] = []

        if !overdueTasks.isEmpty {
            items.append(
                DashboardAlertItem(
                    id: "overdue",
                    title: language.localized("Overdue tasks", "Tareas vencidas"),
                    detail: language.localized(
                        "\(overdueTasks.count) tasks are already past due and should be reviewed first.",
                        "\(overdueTasks.count) tareas ya han vencido y conviene revisarlas primero."
                    ),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: Color(red: 0.83, green: 0.24, blue: 0.27)
                )
            )
        }

        if !dueTodayTasks.isEmpty {
            items.append(
                DashboardAlertItem(
                    id: "today",
                    title: language.localized("Due today", "Vencen hoy"),
                    detail: language.localized(
                        "\(dueTodayTasks.count) tasks expire today and can be tackled from the land detail screens.",
                        "\(dueTodayTasks.count) tareas vencen hoy y puedes resolverlas desde las fichas de terreno."
                    ),
                    systemImage: "calendar.badge.clock",
                    tint: Color(red: 0.96, green: 0.66, blue: 0.18)
                )
            )
        }

        if syncErrorCount > 0 {
            items.append(
                DashboardAlertItem(
                    id: "sync_error",
                    title: language.localized("Sync needs review", "La sincronización necesita revisión"),
                    detail: language.localized(
                        "\(syncErrorCount) queued changes have errors and may need manual retry from the account screen.",
                        "\(syncErrorCount) cambios en cola tienen errores y pueden requerir reintento manual desde la cuenta."
                    ),
                    systemImage: "arrow.triangle.2.circlepath.circle.fill",
                    tint: Color(red: 0.83, green: 0.24, blue: 0.27)
                )
            )
        } else if pendingSyncCount > 0 {
            items.append(
                DashboardAlertItem(
                    id: "sync_pending",
                    title: language.localized("Sync in progress", "Sincronización en curso"),
                    detail: language.localized(
                        "\(pendingSyncCount) local changes are still waiting to upload.",
                        "\(pendingSyncCount) cambios locales siguen pendientes de subir."
                    ),
                    systemImage: "icloud.and.arrow.up.fill",
                    tint: Color(red: 0.57, green: 0.46, blue: 0.92)
                )
            )
        }

        if offlineDeviceCount > 0 {
            items.append(
                DashboardAlertItem(
                    id: "offline_devices",
                    title: language.localized("Offline devices", "Dispositivos desconectados"),
                    detail: language.localized(
                        "\(offlineDeviceCount) active devices have stale signal or a link error.",
                        "\(offlineDeviceCount) dispositivos activos tienen señal antigua o error de enlace."
                    ),
                    systemImage: "dot.radiowaves.left.and.right",
                    tint: Color(red: 0.91, green: 0.45, blue: 0.20)
                )
            )
        }

        if lowBatteryDeviceCount > 0 {
            items.append(
                DashboardAlertItem(
                    id: "battery",
                    title: language.localized("Low battery", "Batería baja"),
                    detail: language.localized(
                        "\(lowBatteryDeviceCount) devices report battery under 20%.",
                        "\(lowBatteryDeviceCount) dispositivos reportan batería por debajo del 20%."
                    ),
                    systemImage: "battery.25",
                    tint: Color(red: 0.95, green: 0.58, blue: 0.20)
                )
            )
        }

        if roleAccessViewModel.canManageStructure && ungroupedLandCount > 0 {
            items.append(
                DashboardAlertItem(
                    id: "ungrouped",
                    title: language.localized("Ungrouped lands", "Terrenos sin grupo"),
                    detail: language.localized(
                        "\(ungroupedLandCount) lands are still ungrouped, which makes the structure harder to scan.",
                        "\(ungroupedLandCount) terrenos siguen sin grupo, lo que dificulta leer la estructura."
                    ),
                    systemImage: "square.grid.2x2",
                    tint: Color(red: 0.12, green: 0.43, blue: 0.86)
                )
            )
        }

        return items
    }

    private var incomeTrendPoints: [DashboardTrendPoint] {
        guard !historyEntries.isEmpty else { return [] }

        let grouped = Dictionary(grouping: historyEntries, by: \.periodKey)
        let latestPeriod = historyEntries
            .map(\.periodDate)
            .max() ?? startOfToday

        let latestMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: latestPeriod)) ?? latestPeriod

        return (0..<6).compactMap { index in
            guard let monthDate = calendar.date(byAdding: .month, value: index - 5, to: latestMonth) else {
                return nil
            }

            let components = calendar.dateComponents([.year, .month], from: monthDate)
            guard let year = components.year, let month = components.month else { return nil }

            let key = year * 100 + month
            let total = (grouped[key] ?? []).reduce(0) { partialResult, entry in
                partialResult + max(0, entry.incomeAmount)
            }

            return DashboardTrendPoint(date: monthDate, value: total)
        }
    }

    private var attentionLands: [DashboardLandAttentionItem] {
        Array(
            lands.compactMap { land in
                let overdueCount = land.tasks.filter { !$0.isCompleted && $0.dueDate < startOfToday }.count
                let dueTodayCount = land.tasks.filter { !$0.isCompleted && $0.dueDate >= startOfToday && $0.dueDate < endOfToday }.count
                let offlineCount = land.devices.filter { $0.isActive && isDeviceOffline($0) }.count
                let lowBatteryCount = land.devices.filter { $0.isActive && isLowBattery($0) }.count
                let isUngrouped = land.group == nil
                let hasNegativeMargin = roleAccessViewModel.canViewEconomics && land.annualNetMargin < 0

                let score =
                    (overdueCount * 5) +
                    (dueTodayCount * 3) +
                    (offlineCount * 4) +
                    (lowBatteryCount * 2) +
                    (isUngrouped ? 1 : 0) +
                    (hasNegativeMargin ? 2 : 0)

                guard score > 0 else { return nil }

                return DashboardLandAttentionItem(
                    id: land.id,
                    land: land,
                    overdueTasks: overdueCount,
                    dueTodayTasks: dueTodayCount,
                    offlineDevices: offlineCount,
                    lowBatteryDevices: lowBatteryCount,
                    isUngrouped: isUngrouped,
                    hasNegativeMargin: hasNegativeMargin,
                    score: score
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.land.name.localizedCaseInsensitiveCompare(rhs.land.name) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
            .prefix(3)
        )
    }

    private var heroSubtitle: String {
        if lands.isEmpty {
            return language.localized(
                "Create your first parcel to start mapping crop, energy and field operations from one visual workspace.",
                "Crea tu primera parcela para empezar a leer cultivo, energía y operativa de campo desde un único espacio visual."
            )
        }

        if hasEnergyLands {
            return language.localized(
                "Your dual-use portfolio is live. Review parcel readiness, operations and field evidence from here.",
                "Tu portfolio de doble uso ya está activo. Revisa desde aquí la preparación de las parcelas, la operación y la evidencia de campo."
            )
        }

        if !overdueTasks.isEmpty {
            return language.localized(
                "You have \(overdueTasks.count) overdue tasks and \(dueTodayTasks.count) due today. Start with the critical lands below.",
                "Tienes \(overdueTasks.count) tareas vencidas y \(dueTodayTasks.count) para hoy. Empieza por los terrenos críticos de abajo."
            )
        }

        if syncErrorCount > 0 {
            return language.localized(
                "Most operations look healthy, but sync still has \(syncErrorCount) issues waiting for review.",
                "La operación va bien, pero la sincronización todavía tiene \(syncErrorCount) incidencias pendientes de revisar."
            )
        }

        if pendingSyncCount > 0 {
            return language.localized(
                "The workspace is moving: \(pendingSyncCount) local changes are still queued for cloud sync.",
                "El espacio de trabajo está en marcha: \(pendingSyncCount) cambios locales siguen en cola para sincronizar."
            )
        }

        if offlineDeviceCount > 0 {
            return language.localized(
                "Work is mostly on track, but \(offlineDeviceCount) devices need a quick connectivity check.",
                "La operativa va bien, pero \(offlineDeviceCount) dispositivos necesitan una revisión rápida de conectividad."
            )
        }

        return language.localized(
            "Everything looks stable right now. Use this tab as the visual starting point for parcel health, viability and execution.",
            "Ahora mismo todo parece estable. Usa esta pestaña como punto de partida visual para salud de parcela, viabilidad y ejecución."
        )
    }

    private var dualUseLensSubtitle: String {
        if lands.isEmpty {
            return language.localized(
                "The current schema already supports a first agrovoltaic workflow: parcel, cadastre, history, devices and energy fields.",
                "El esquema actual ya soporta un primer flujo agrovoltaico: parcela, catastro, histórico, dispositivos y campos energéticos."
            )
        }

        if hasEnergyLands {
            return language.localized(
                "Quick read of how much of the portfolio is already documented well enough to justify crop + energy decisions.",
                "Lectura rápida de cuánto del portfolio ya está documentado lo bastante bien como para justificar decisiones de cultivo + energía."
            )
        }

        return language.localized(
            "You can start the agrovoltaic lens without changing the backend: classify parcels, map them and build evidence over time.",
            "Puedes arrancar el enfoque agrovoltaico sin cambiar backend: clasifica parcelas, mapea y construye evidencia con el tiempo."
        )
    }

    private var dualUseLensNarrative: String {
        if lands.isEmpty {
            return language.localized(
                "Start with one candidate parcel and import its cadastre footprint first. The rest of the workspace already knows how to store tasks, history, telemetry and energy values around that parcel.",
                "Empieza con una parcela candidata e importa primero su huella catastral. El resto del espacio ya sabe guardar tareas, histórico, telemetría y valores energéticos alrededor de esa parcela."
            )
        }

        if hasEnergyLands {
            return language.localized(
                "\(dualUseReadyLandCount) parcels already combine at least three proof layers: mapping, historical records, sensors or energy configuration.",
                "\(dualUseReadyLandCount) parcelas ya combinan al menos tres capas de prueba: cartografía, histórico, sensores o configuración energética."
            )
        }

        return language.localized(
            "None of the parcels are marked as energy-enabled yet, but \(landsWithCadastreCount) already have cadastre context and \(landsWithHistoryCount) already have historical evidence to build on.",
            "Todavía no hay parcelas marcadas como energéticas, pero \(landsWithCadastreCount) ya tienen contexto catastral y \(landsWithHistoryCount) ya tienen evidencia histórica sobre la que construir."
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dashboardHeroCard
                    dualUseLensCard
                    attentionCenterCard
                    overviewCard

                    if roleAccessViewModel.canViewEconomics && !incomeTrendPoints.isEmpty {
                        incomeTrendCard
                    }

                    upcomingTasksCard
                    landsNeedingAttentionCard
                    quickActionsCard
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(language.localized("Dashboard", "Dashboard"))
            .navigationDestination(for: Land.self) { land in
                LandDetailView(land: land)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    SettingsToolbarButton {
                        showingSettings = true
                    }

                    AccountToolbarButton {
                        showingAccount = true
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
            .sheet(isPresented: $showingCreateLand) {
                LandEditorView(mode: .create)
            }
            .sheet(isPresented: $showingCreateGroup) {
                GroupEditorView()
            }
            .sheet(isPresented: $showingTeam) {
                TeamView()
            }
        }
    }

    private var dashboardHeroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.43, blue: 0.86),
                            Color(red: 0.16, green: 0.67, blue: 0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            hasEnergyLands
                                ? language.localized("Dual-Use Workspace", "Espacio de doble uso")
                                : language.localized("Visual Parcel Workspace", "Espacio visual de parcelas")
                        )
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(heroSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LazyVGrid(columns: heroGridColumns, spacing: 10) {
                    GlassHeroSummaryTile(
                        title: language.localized("Lands", "Terrenos"),
                        value: "\(lands.count)",
                        systemImage: "leaf.fill",
                        colors: [Color(red: 0.17, green: 0.55, blue: 0.93), Color(red: 0.13, green: 0.44, blue: 0.82)]
                    )

                    GlassHeroSummaryTile(
                        title: language.localized("Groups", "Grupos"),
                        value: "\(groups.count)",
                        systemImage: "square.grid.2x2.fill",
                        colors: [Color(red: 0.19, green: 0.66, blue: 0.40), Color(red: 0.16, green: 0.54, blue: 0.31)]
                    )

                    GlassHeroSummaryTile(
                        title: language.localized("Pending Tasks", "Tareas pendientes"),
                        value: "\(pendingTasks.count)",
                        systemImage: "checklist",
                        colors: [Color(red: 0.96, green: 0.66, blue: 0.18), Color(red: 0.91, green: 0.45, blue: 0.20)]
                    )

                    GlassHeroSummaryTile(
                        title: language.localized("Sync", "Sincronización"),
                        value: pendingSyncCount == 0
                            ? language.localized("Ready", "Lista")
                            : "\(pendingSyncCount)",
                        systemImage: "arrow.triangle.2.circlepath",
                        colors: [Color(red: 0.57, green: 0.46, blue: 0.92), Color(red: 0.34, green: 0.39, blue: 0.82)]
                    )
                }
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    private var dualUseLensCard: some View {
        GlassPanelCard(
            title: language.localized("Agrovoltaic Lens", "Lente agrovoltaica"),
            subtitle: dualUseLensSubtitle,
            systemImage: "solarpanel",
            tint: Color(red: 0.86, green: 0.46, blue: 0.12)
        ) {
            if lands.isEmpty {
                dashboardEmptyState(
                    title: language.localized("No candidate parcels yet", "Aún no hay parcelas candidatas"),
                    subtitle: language.localized(
                        "Create one parcel and its first agrovoltaic readiness signals will appear here.",
                        "Crea una parcela y aquí aparecerán sus primeras señales de preparación agrovoltaica."
                    ),
                    systemImage: "map.fill",
                    tint: Color(red: 0.86, green: 0.46, blue: 0.12)
                )
            } else {
                LazyVGrid(columns: heroGridColumns, spacing: 10) {
                    DashboardMetricTile(
                        item: DashboardMetricItem(
                            id: "agrovoltaic_candidates",
                            title: language.localized("Agrovoltaic", "Agrovoltaicas"),
                            value: "\(agrovoltaicLandCount)",
                            subtitle: language.localized("Parcels already tagged", "Parcelas ya etiquetadas"),
                            tint: Color(red: 0.86, green: 0.46, blue: 0.12)
                        )
                    )

                    DashboardMetricTile(
                        item: DashboardMetricItem(
                            id: "cadastre_ready",
                            title: language.localized("Cadastre", "Catastro"),
                            value: "\(landsWithCadastreCount)",
                            subtitle: language.localized("With mapped footprint", "Con huella mapeada"),
                            tint: Color(red: 0.16, green: 0.46, blue: 0.95)
                        )
                    )

                    DashboardMetricTile(
                        item: DashboardMetricItem(
                            id: "history_ready",
                            title: language.localized("Field Records", "Evidencia"),
                            value: "\(landsWithHistoryCount)",
                            subtitle: language.localized("With historical data", "Con datos históricos"),
                            tint: Color(red: 0.19, green: 0.66, blue: 0.40)
                        )
                    )

                    DashboardMetricTile(
                        item: DashboardMetricItem(
                            id: "telemetry_ready",
                            title: language.localized("Telemetry", "Telemetría"),
                            value: "\(monitoredLandCount)",
                            subtitle: language.localized("Parcels with devices", "Parcelas con dispositivos"),
                            tint: Color(red: 0.57, green: 0.46, blue: 0.92)
                        )
                    )
                }

                Text(dualUseLensNarrative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var attentionCenterCard: some View {
        GlassPanelCard(
            title: language.localized("Attention Center", "Centro de atención"),
            subtitle: language.localized("The highest-priority signals across tasks, sync and devices.", "Las señales de mayor prioridad entre tareas, sincronización y dispositivos."),
            systemImage: "exclamationmark.bubble.fill",
            tint: Color(red: 0.91, green: 0.45, blue: 0.20)
        ) {
            if attentionAlerts.isEmpty {
                dashboardEmptyState(
                    title: lands.isEmpty
                        ? language.localized("Nothing to monitor yet", "Todavía no hay nada que vigilar")
                        : language.localized("Everything looks healthy", "Todo parece saludable"),
                    subtitle: lands.isEmpty
                        ? language.localized("Create a land to start surfacing operational alerts here.", "Crea un terreno para que aquí empiecen a aparecer alertas operativas.")
                        : language.localized("No overdue tasks, no sync blockers and no device warnings at the moment.", "Ahora mismo no hay tareas vencidas, bloqueos de sincronización ni avisos de dispositivos."),
                    systemImage: lands.isEmpty ? "leaf.circle.fill" : "checkmark.seal.fill",
                    tint: lands.isEmpty ? Color(red: 0.12, green: 0.43, blue: 0.86) : Color(red: 0.16, green: 0.67, blue: 0.58)
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(attentionAlerts) { item in
                        dashboardAlertRow(item)
                    }
                }
            }

            if pendingSyncCount > 0 || syncErrorCount > 0 {
                Button {
                    showingAccount = true
                } label: {
                    Label(language.localized("Review sync status", "Revisar estado de sincronización"), systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else if lands.isEmpty && roleAccessViewModel.canManageStructure {
                Button {
                    showingCreateLand = true
                } label: {
                    Label(language.localized("Create first land", "Crear primer terreno"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.43, blue: 0.86))
            }
        }
    }

    private var overviewCard: some View {
        GlassPanelCard(
            title: roleAccessViewModel.canViewEconomics
                ? (
                    hasEnergyLands
                        ? language.localized("Portfolio & Viability", "Portfolio y viabilidad")
                        : language.localized("Portfolio Overview", "Resumen del portfolio")
                )
                : language.localized("Operations Overview", "Resumen operativo"),
            subtitle: roleAccessViewModel.canViewEconomics
                ? (
                    hasEnergyLands
                        ? language.localized("Cross-parcel snapshot for crop, energy, economics and device health.", "Vista transversal por parcela para cultivo, energía, economía y salud de dispositivos.")
                        : language.localized("Cross-land snapshot for structure, finance and device health.", "Vista transversal de estructura, finanzas y salud de dispositivos.")
                )
                : language.localized("Quick snapshot for structure, workload and operational health.", "Vista rápida de estructura, carga de trabajo y salud operativa."),
            systemImage: "chart.bar.doc.horizontal.fill",
            tint: Color(red: 0.12, green: 0.43, blue: 0.86)
        ) {
            LazyVGrid(columns: heroGridColumns, spacing: 10) {
                ForEach(overviewMetrics) { item in
                    DashboardMetricTile(item: item)
                }
            }
        }
    }

    private var incomeTrendCard: some View {
        GlassPanelCard(
            title: language.localized("Income Trend", "Tendencia de ingresos"),
            subtitle: language.localized("Aggregated from the latest six registered historical months.", "Agregado a partir de los últimos seis meses históricos registrados."),
            systemImage: "chart.xyaxis.line",
            tint: Color(red: 0.96, green: 0.66, blue: 0.18)
        ) {
            Chart(incomeTrendPoints) { point in
                AreaMark(
                    x: .value("Month", point.date, unit: .month),
                    y: .value("Income", point.value)
                )
                .foregroundStyle(Color(red: 0.96, green: 0.66, blue: 0.18).opacity(0.16))

                LineMark(
                    x: .value("Month", point.date, unit: .month),
                    y: .value("Income", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color(red: 0.96, green: 0.66, blue: 0.18))

                PointMark(
                    x: .value("Month", point.date, unit: .month),
                    y: .value("Income", point.value)
                )
                .foregroundStyle(Color(red: 0.91, green: 0.45, blue: 0.20))
            }
            .frame(height: 180)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(6, incomeTrendPoints.count))) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }

            HStack(spacing: 10) {
                DashboardMiniHighlight(
                    title: language.localized("Latest Month", "Último mes"),
                    value: (incomeTrendPoints.last?.value ?? 0).formatted(.currency(code: currencyCode)),
                    tint: Color(red: 0.96, green: 0.66, blue: 0.18)
                )

                DashboardMiniHighlight(
                    title: language.localized("6M Total", "Total 6M"),
                    value: incomeTrendPoints.reduce(0) { $0 + $1.value }.formatted(.currency(code: currencyCode)),
                    tint: Color(red: 0.12, green: 0.43, blue: 0.86)
                )
            }
        }
    }

    private var upcomingTasksCard: some View {
        GlassPanelCard(
            title: language.localized("Upcoming Tasks", "Próximas tareas"),
            subtitle: language.localized("Ordered globally by due date so you can start from the nearest commitments.", "Ordenadas globalmente por vencimiento para empezar por los compromisos más cercanos."),
            systemImage: "calendar.badge.clock",
            tint: Color(red: 0.16, green: 0.46, blue: 0.95)
        ) {
            if upcomingTasks.isEmpty {
                dashboardEmptyState(
                    title: language.localized("No pending tasks", "No hay tareas pendientes"),
                    subtitle: lands.isEmpty
                        ? language.localized("Create a land first, then add operational tasks from its detail screen.", "Crea primero un terreno y luego añade tareas operativas desde su ficha.")
                        : language.localized("Open any land to create irrigation, pruning, harvest or maintenance follow-up.", "Abre cualquier terreno para crear seguimientos de riego, poda, cosecha o mantenimiento."),
                    systemImage: "checkmark.circle.fill",
                    tint: Color(red: 0.16, green: 0.67, blue: 0.58)
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(upcomingTasks) { task in
                        dashboardTaskRow(task)
                    }
                }
            }
        }
    }

    private var landsNeedingAttentionCard: some View {
        GlassPanelCard(
            title: language.localized("Lands Needing Attention", "Terrenos que requieren atención"),
            subtitle: language.localized("Prioritized by overdue work, device health and structural gaps.", "Priorizados por tareas vencidas, salud de dispositivos y huecos estructurales."),
            systemImage: "scope",
            tint: Color(red: 0.57, green: 0.46, blue: 0.92)
        ) {
            if attentionLands.isEmpty {
                dashboardEmptyState(
                    title: language.localized("No critical lands right now", "Ahora mismo no hay terrenos críticos"),
                    subtitle: language.localized("As soon as tasks, device issues or structural gaps appear, they will surface here.", "En cuanto aparezcan tareas, incidencias de dispositivos o huecos estructurales, los verás aquí."),
                    systemImage: "leaf.fill",
                    tint: Color(red: 0.16, green: 0.67, blue: 0.58)
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(attentionLands) { item in
                        NavigationLink(value: item.land) {
                            DashboardLandAttentionRow(
                                item: item,
                                language: language,
                                currencyCode: currencyCode,
                                issueSummary: attentionSummary(for: item)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var quickActionsCard: some View {
        GlassPanelCard(
            title: language.localized("Quick Actions", "Acciones rápidas"),
            subtitle: language.localized("Shortcuts for the most common moves without leaving the dashboard.", "Atajos para los movimientos más comunes sin salir del dashboard."),
            systemImage: "bolt.circle.fill",
            tint: Color(red: 0.16, green: 0.67, blue: 0.58)
        ) {
            LazyVGrid(columns: heroGridColumns, spacing: 10) {
                if roleAccessViewModel.canManageStructure {
                    DashboardQuickActionButton(
                        title: language.localized("New Land", "Nuevo terreno"),
                        subtitle: language.localized("Add parcel data", "Añadir parcela"),
                        systemImage: "plus.circle.fill",
                        tint: Color(red: 0.12, green: 0.43, blue: 0.86)
                    ) {
                        showingCreateLand = true
                    }

                    DashboardQuickActionButton(
                        title: language.localized("New Group", "Nuevo grupo"),
                        subtitle: language.localized("Organize lands", "Organizar terrenos"),
                        systemImage: "square.grid.2x2.fill",
                        tint: Color(red: 0.19, green: 0.66, blue: 0.40)
                    ) {
                        showingCreateGroup = true
                    }
                }

                if roleAccessViewModel.canManageTeam {
                    DashboardQuickActionButton(
                        title: language.localized("Team", "Equipo"),
                        subtitle: language.localized("Members and invites", "Miembros e invitaciones"),
                        systemImage: "person.2.fill",
                        tint: Color(red: 0.20, green: 0.66, blue: 0.39)
                    ) {
                        showingTeam = true
                    }
                }

                DashboardQuickActionButton(
                    title: language.localized("Account", "Cuenta"),
                    subtitle: pendingSyncCount == 0
                        ? language.localized("Sync healthy", "Sync estable")
                        : language.localized("\(pendingSyncCount) pending", "\(pendingSyncCount) pendientes"),
                    systemImage: pendingSyncCount == 0 ? "person.crop.circle" : "arrow.triangle.2.circlepath.circle.fill",
                    tint: pendingSyncCount == 0
                        ? Color(red: 0.57, green: 0.46, blue: 0.92)
                        : Color(red: 0.91, green: 0.45, blue: 0.20)
                ) {
                    showingAccount = true
                }

                DashboardQuickActionButton(
                    title: language.localized("Settings", "Ajustes"),
                    subtitle: language.localized("Language, units, currency", "Idioma, unidades, moneda"),
                    systemImage: "slider.horizontal.3",
                    tint: Color(red: 0.40, green: 0.45, blue: 0.55)
                ) {
                    showingSettings = true
                }
            }
        }
    }

    private var heroGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: 10),
            GridItem(.flexible(minimum: 0), spacing: 10)
        ]
    }

    private func isDeviceOffline(_ device: LandDevice) -> Bool {
        if device.linkState == .error || device.linkState == .unlinked {
            return true
        }

        guard device.linkMethod != .manual else { return false }
        guard let lastSeenAt = device.lastSeenAt else { return false }
        return lastSeenAt < sixHoursAgo
    }

    private func hasCadastreData(for land: Land) -> Bool {
        land.catastroRefcat14 != nil || !land.catastroRings.flatMap { $0 }.isEmpty
    }

    private func dualUseReadinessScore(for land: Land) -> Int {
        var score = 0

        if hasCadastreData(for: land) {
            score += 1
        }

        if !land.historyEntries.isEmpty {
            score += 1
        }

        if !land.devices.isEmpty {
            score += 1
        }

        if ActivityCatalog.supportsEnergyMetrics(activityType: land.activityType) &&
            (land.installedCapacityKW > 0 || land.annualElectricityProductionKWh > 0) {
            score += 1
        }

        return score
    }

    private func isLowBattery(_ device: LandDevice) -> Bool {
        guard let batteryLevel = device.batteryLevel else { return false }
        return batteryLevel > 0 && batteryLevel < 20
    }

    private func attentionSummary(for item: DashboardLandAttentionItem) -> String {
        var parts: [String] = []

        if item.overdueTasks > 0 {
            parts.append(language.localized("\(item.overdueTasks) overdue tasks", "\(item.overdueTasks) tareas vencidas"))
        }

        if item.dueTodayTasks > 0 {
            parts.append(language.localized("\(item.dueTodayTasks) due today", "\(item.dueTodayTasks) para hoy"))
        }

        if item.offlineDevices > 0 {
            parts.append(language.localized("\(item.offlineDevices) offline devices", "\(item.offlineDevices) dispositivos desconectados"))
        }

        if item.lowBatteryDevices > 0 {
            parts.append(language.localized("\(item.lowBatteryDevices) low battery", "\(item.lowBatteryDevices) con batería baja"))
        }

        if item.isUngrouped {
            parts.append(language.localized("ungrouped", "sin grupo"))
        }

        if item.hasNegativeMargin {
            parts.append(language.localized("negative margin", "margen negativo"))
        }

        return parts.joined(separator: " · ")
    }

    private func taskStatusLabel(for task: LandTask) -> String {
        if task.dueDate < startOfToday {
            return language.localized("Overdue", "Vencida")
        }

        if calendar.isDateInToday(task.dueDate) {
            return language.localized("Today", "Hoy")
        }

        if calendar.isDateInTomorrow(task.dueDate) {
            return language.localized("Tomorrow", "Mañana")
        }

        return task.dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func taskStatusTint(for task: LandTask) -> Color {
        if task.dueDate < startOfToday {
            return Color(red: 0.83, green: 0.24, blue: 0.27)
        }

        if calendar.isDateInToday(task.dueDate) {
            return Color(red: 0.91, green: 0.45, blue: 0.20)
        }

        return Color(red: 0.12, green: 0.43, blue: 0.86)
    }

    @ViewBuilder
    private func dashboardTaskRow(_ task: LandTask) -> some View {
        if let land = task.land {
            NavigationLink(value: land) {
                dashboardTaskRowContent(task)
            }
            .buttonStyle(.plain)
        } else {
            dashboardTaskRowContent(task)
        }
    }

    private func dashboardTaskRowContent(_ task: LandTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.type.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(taskStatusTint(for: task))
                .frame(width: 38, height: 38)
                .background(taskStatusTint(for: task).opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(task.land?.name ?? language.localized("No land assigned", "Sin terreno asignado"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(taskStatusLabel(for: task))
                .font(.caption.weight(.semibold))
                .foregroundStyle(taskStatusTint(for: task))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(taskStatusTint(for: task).opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(taskStatusTint(for: task).opacity(0.14), lineWidth: 1)
        )
    }

    private func dashboardAlertRow(_ item: DashboardAlertItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.tint)
                .frame(width: 38, height: 38)
                .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.tint.opacity(0.16), lineWidth: 1)
        )
    }

    private func dashboardEmptyState(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct DashboardAlertItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
}

private struct DashboardMetricItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
}

private struct DashboardTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

private struct DashboardLandAttentionItem: Identifiable {
    let id: UUID
    let land: Land
    let overdueTasks: Int
    let dueTodayTasks: Int
    let offlineDevices: Int
    let lowBatteryDevices: Int
    let isUngrouped: Bool
    let hasNegativeMargin: Bool
    let score: Int
}

private struct DashboardMetricTile: View {
    let item: DashboardMetricItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(item.tint)

            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(item.value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(item.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.tint.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct DashboardMiniHighlight: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct DashboardLandAttentionRow: View {
    let item: DashboardLandAttentionItem
    let language: AppLanguage
    let currencyCode: String
    let issueSummary: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.57, green: 0.46, blue: 0.92))
                .frame(width: 38, height: 38)
                .background(
                    Color(red: 0.57, green: 0.46, blue: 0.92).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.land.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.land.group?.name ?? language.localized("Ungrouped", "Sin grupo"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(issueSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if item.hasNegativeMargin {
                Text(item.land.annualNetMargin.formatted(.currency(code: currencyCode)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
            } else if item.offlineDevices > 0 || item.overdueTasks > 0 {
                Text("\(max(item.offlineDevices, item.overdueTasks))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.91, green: 0.45, blue: 0.20))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Color(red: 0.91, green: 0.45, blue: 0.20).opacity(0.12),
                        in: Capsule()
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.57, green: 0.46, blue: 0.92).opacity(0.14), lineWidth: 1)
        )
    }
}

private struct DashboardQuickActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
