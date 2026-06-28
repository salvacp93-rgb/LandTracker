import SwiftUI
import MapKit
import SwiftData

struct GroupDetailView: View {
    @Query(sort: \Land.name) private var allLands: [Land]
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @AppStorage(AccountPreferences.measurementSystemKey) private var measurementSystemRaw = AppSettings.defaultMeasurementSystem.rawValue
    @AppStorage(AccountPreferences.preferredCurrencyCodeKey) private var preferredCurrencyCode = AppSettings.defaultCurrency.rawValue
    let group: LandGroup

    @State private var position: MapCameraPosition = .region(Self.defaultRegion())
    @State private var selectedLandRoute: GroupLandRoute?

    private var lands: [Land] {
        group.lands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var groupColor: Color {
        Color(hex: group.colorHex)
    }

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var measurementSystem: AppMeasurementSystem {
        AppSettings.measurementSystem(from: measurementSystemRaw)
    }

    private var currencyCode: String {
        AppSettings.currencyCode(from: preferredCurrencyCode)
    }

    private var totalIncome: Double {
        lands.reduce(0) { $0 + $1.incomeAnnual }
    }

    private var totalExpenses: Double {
        lands.reduce(0) { $0 + $1.annualTotalExpenses }
    }

    private var netMargin: Double {
        totalIncome - totalExpenses
    }

    private var totalAcres: Double {
        lands.reduce(0) { $0 + max(0, $1.sizeAcres) }
    }

    private var averageIncome: Double {
        guard !lands.isEmpty else { return 0 }
        return totalIncome / Double(lands.count)
    }

    private var totalCapacityKW: Double {
        lands.reduce(0) { $0 + max(0, $1.installedCapacityKW) }
    }

    private var totalElectricityKWh: Double {
        lands.reduce(0) { $0 + max(0, $1.annualElectricityProductionKWh) }
    }

    private var averageSelfConsumptionRate: Double {
        let energyLands = lands.filter { ActivityCatalog.supportsEnergyMetrics(activityType: $0.activityType) }
        guard !energyLands.isEmpty else { return 0 }
        let total = energyLands.reduce(0) { $0 + max(0, $1.selfConsumptionRate) }
        return total / Double(energyLands.count)
    }

    private var energyLandsCount: Int {
        lands.filter { ActivityCatalog.supportsEnergyMetrics(activityType: $0.activityType) }.count
    }

    private var hasEnergyLands: Bool {
        energyLandsCount > 0
    }

    private var productionBreakdown: [(rawName: String, displayName: String, count: Int)] {
        let grouped = Dictionary(grouping: lands) { land in
            let name = land.productionType.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Unspecified" : name
        }
        return grouped
            .map { entry in
                let displayName = entry.key == "Unspecified"
                    ? language.localized("Unspecified", "Sin definir")
                    : ProductionCatalog.displayName(for: entry.key, language: language)
                return (rawName: entry.key, displayName: displayName, count: entry.value.count)
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.displayName < $1.displayName
                }
                return $0.count > $1.count
            }
    }

    private var topProduction: String {
        productionBreakdown.first?.displayName ?? language.localized("N/A", "N/D")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                mapCard
                if roleAccessViewModel.canViewEconomics {
                    metricsGrid
                }
                productionCard
                landsCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedLandRoute) { route in
            if let land = allLands.first(where: { $0.id == route.landID }) {
                LandDetailView(land: land)
            } else {
                Text(language.localized("Land not found", "Terreno no encontrado"))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            position = .region(regionForLands(lands))
        }
        .onChange(of: lands.map(\.id)) { _, _ in
            position = .region(regionForLands(lands))
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(groupColor)
                    .frame(width: 12, height: 12)

                Text(group.name)
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("\(lands.count) \(language.localized("lands", "terrenos"))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if roleAccessViewModel.canViewEconomics {
                        GroupPillStat(icon: "dollarsign.circle", label: totalIncome.formatted(.currency(code: currencyCode)))
                    }
                    GroupPillStat(
                        icon: "map",
                        label: "\(AppSettings.areaValue(fromAcres: totalAcres, system: measurementSystem).formatted(.number.precision(.fractionLength(1)))) \(AppSettings.areaShortUnit(system: measurementSystem))"
                    )
                    if hasEnergyLands {
                        GroupPillStat(
                            icon: "bolt.circle",
                            label: "\(totalCapacityKW.formatted(.number.precision(.fractionLength(1)))) kW"
                        )
                    } else {
                        GroupPillStat(icon: "leaf", label: topProduction)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [groupColor.opacity(0.22), groupColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(groupColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.localized("Map Snapshot", "Mini mapa"))
                    .font(.headline)
                Spacer()
                Text(language.localized("Mini view", "Vista rápida"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if lands.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 170)
                    .overlay {
                        Text(language.localized("Add lands to see this group's map", "Añade terrenos para ver el mapa del grupo"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
            } else {
                Map(position: $position) {
                    ForEach(lands) { land in
                        ForEach(land.catastroRings.indices, id: \.self) { index in
                            let ring = land.catastroRings[index]
                            if !ring.isEmpty {
                                MapPolygon(coordinates: ring.map { $0.clLocation })
                                    .foregroundStyle(groupColor.opacity(0.2))
                                    .stroke(groupColor, lineWidth: 1.5)
                            }
                        }
                    }

                    ForEach(lands) { land in
                        if land.catastroRings.allSatisfy(\.isEmpty) {
                            MapCircle(center: land.coordinate, radius: 90)
                                .foregroundStyle(groupColor.opacity(0.2))
                                .stroke(groupColor, lineWidth: 1.5)
                        }
                    }
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupMetricModeHeader(
                title: hasEnergyLands
                    ? language.localized("Energy Group Overview", "Resumen de grupo energético")
                    : language.localized("Agricultural Group Overview", "Resumen de grupo agrícola"),
                subtitle: hasEnergyLands
                    ? language.localized("Showing agrovoltaic/electricity metrics only where applicable.", "Mostrando métricas agrovoltaicas/eléctricas solo cuando aplican.")
                    : language.localized("Energy generation metrics are hidden for non-energy groups.", "Las métricas de generación eléctrica se ocultan en grupos no energéticos.")
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                GroupMetricCard(
                    title: language.localized("Total Income", "Ingresos totales"),
                    value: totalIncome.formatted(.currency(code: currencyCode)),
                    icon: "banknote"
                )

                GroupMetricCard(
                    title: language.localized("Average / Land", "Promedio / terreno"),
                    value: averageIncome.formatted(.currency(code: currencyCode)),
                    icon: "chart.bar.xaxis"
                )

                GroupMetricCard(
                    title: language.localized("Total Expenses", "Gastos totales"),
                    value: totalExpenses.formatted(.currency(code: currencyCode)),
                    icon: "creditcard"
                )

                GroupMetricCard(
                    title: language.localized("Net Margin", "Margen neto"),
                    value: netMargin.formatted(.currency(code: currencyCode)),
                    icon: "chart.line.uptrend.xyaxis"
                )

                GroupMetricCard(
                    title: language.localized("Total Area", "Superficie total"),
                    value: AppSettings.formatArea(
                        acres: totalAcres,
                        system: measurementSystem,
                        language: language,
                        fractionDigits: 2
                    ),
                    icon: "square.3.layers.3d"
                )

                if hasEnergyLands {
                    GroupMetricCard(
                        title: language.localized("Installed kW", "kW instalados"),
                        value: "\(totalCapacityKW.formatted(.number.precision(.fractionLength(1)))) kW",
                        icon: "bolt.circle"
                    )

                    GroupMetricCard(
                        title: language.localized("Electricity / Year", "Electricidad / año"),
                        value: "\(totalElectricityKWh.formatted(.number.precision(.fractionLength(1)))) kWh",
                        icon: "bolt.horizontal.circle"
                    )

                    GroupMetricCard(
                        title: language.localized("Avg. Self Consumption", "Autoconsumo medio"),
                        value: "\(averageSelfConsumptionRate.formatted(.number.precision(.fractionLength(1))))%",
                        icon: "gauge.with.dots.needle.67percent"
                    )
                }
            }
        }
    }

    private var productionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.localized("Production Mix", "Distribución de producción"))
                .font(.headline)

            if productionBreakdown.isEmpty {
                Text(language.localized("No production data yet", "Aún no hay datos de producción"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(productionBreakdown, id: \.rawName) { item in
                    HStack {
                        Text(item.displayName)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count)")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var landsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.localized("Lands", "Terrenos"))
                .font(.headline)

            if lands.isEmpty {
                Text(language.localized("No lands assigned to this group", "No hay terrenos asignados a este grupo"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lands) { land in
                    Button {
                        selectedLandRoute = GroupLandRoute(landID: land.id)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(groupColor.opacity(0.2))
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Circle()
                                        .stroke(groupColor.opacity(0.4), lineWidth: 1)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(land.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(ProductionCatalog.displayName(for: land.productionType, language: language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if roleAccessViewModel.canViewEconomics {
                                Text(land.incomeAnnual, format: .currency(code: currencyCode))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

private struct GroupLandRoute: Hashable, Identifiable {
    let landID: UUID
    var id: UUID { landID }
}

private struct GroupPillStat: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct GroupMetricModeHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct GroupMetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
