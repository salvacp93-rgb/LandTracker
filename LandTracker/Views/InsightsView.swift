import SwiftUI
import SwiftData

struct InsightsView: View {
    @EnvironmentObject private var roleAccess: RoleAccessViewModel
    @Query(sort: \Land.name) private var lands: [Land]
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @AppStorage(AccountPreferences.preferredCurrencyCodeKey) private var preferredCurrencyCode = AppSettings.defaultCurrency.rawValue
    @AppStorage(AccountPreferences.measurementSystemKey) private var measurementSystemRaw = AppSettings.defaultMeasurementSystem.rawValue

    private var language: AppLanguage { AppSettings.language(from: appLanguageRaw) }
    private var currencyCode: String { AppSettings.currencyCode(from: preferredCurrencyCode) }
    private var measurementSystem: AppMeasurementSystem { AppSettings.measurementSystem(from: measurementSystemRaw) }

    private var portfolio: PortfolioInsight { PortfolioInsight(lands: lands) }

    private var allSuggestions: [(land: Land, suggestion: LandSuggestion)] {
        lands.flatMap { land in
            LandEconomicInsight(land: land).suggestions.map { (land, $0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !roleAccess.canViewEconomics {
                    ownerOnlyPlaceholder
                } else if lands.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            portfolioCard
                            if !allSuggestions.isEmpty {
                                suggestionsCard
                            }
                            landBreakdownCard
                        }
                        .padding(16)
                        .padding(.bottom, 28)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .background(AppBackground())
            .navigationTitle(language.localized("Insights", "Estadísticas"))
        }
    }

    // MARK: - Cards

    private var portfolioCard: some View {
        GlassPanelCard(
            title: language.localized("Portfolio", "Portfolio"),
            subtitle: language.localized("Annual plan across all your lands.", "Plan anual en todos tus terrenos."),
            systemImage: "chart.bar.fill",
            tint: AppTheme.olive
        ) {
            LazyVGrid(columns: twoColumns, spacing: 10) {
                insightTile(
                    title: language.localized("Income", "Ingresos"),
                    value: portfolio.totalIncome.formatted(.currency(code: currencyCode)),
                    subtitle: language.localized("Annual plan", "Plan anual"),
                    tint: AppTheme.positive
                )
                insightTile(
                    title: language.localized("Expenses", "Gastos"),
                    value: portfolio.totalExpenses.formatted(.currency(code: currencyCode)),
                    subtitle: language.localized("Irrigation, labor, more", "Riego, mano de obra..."),
                    tint: AppTheme.clay
                )
                insightTile(
                    title: language.localized("Net Margin", "Margen neto"),
                    value: portfolio.totalNetMargin.formatted(.currency(code: currencyCode)),
                    subtitle: portfolio.portfolioMarginRate.map {
                        "\(($0 * 100).formatted(.number.precision(.fractionLength(1))))%"
                    } ?? "—",
                    tint: portfolio.totalNetMargin >= 0
                        ? AppTheme.positive
                        : AppTheme.negative
                )
                insightTile(
                    title: language.localized("Area", "Superficie"),
                    value: "\(AppSettings.areaValue(fromAcres: portfolio.totalAreaAcres, system: measurementSystem).formatted(.number.precision(.fractionLength(1)))) \(AppSettings.areaShortUnit(system: measurementSystem))",
                    subtitle: "\(lands.count) \(language.localized("lands", "terrenos"))",
                    tint: AppTheme.highlight
                )
            }

            if let best = portfolio.bestLand, let worst = portfolio.worstLand {
                HStack(spacing: 10) {
                    landHighlightTile(
                        label: language.localized("Best margin", "Mejor margen"),
                        land: best,
                        tint: AppTheme.positive
                    )
                    landHighlightTile(
                        label: language.localized("Weakest margin", "Margen más débil"),
                        land: worst,
                        tint: AppTheme.negative
                    )
                }
            }
        }
    }

    private var suggestionsCard: some View {
        GlassPanelCard(
            title: language.localized("Suggestions", "Sugerencias"),
            subtitle: language.localized("Based on your plan data and recorded history.", "Basadas en tu plan y el histórico registrado."),
            systemImage: "lightbulb.fill",
            tint: AppTheme.warning
        ) {
            VStack(spacing: 10) {
                ForEach(Array(allSuggestions.enumerated()), id: \.offset) { _, item in
                    suggestionRow(land: item.land, suggestion: item.suggestion)
                }
            }
        }
    }

    private var landBreakdownCard: some View {
        GlassPanelCard(
            title: language.localized("Land Breakdown", "Desglose por terreno"),
            subtitle: language.localized("Net margin rate per land.", "Margen neto por terreno."),
            systemImage: "list.bullet.rectangle",
            tint: AppTheme.highlight
        ) {
            VStack(spacing: 10) {
                ForEach(lands) { land in
                    landBreakdownRow(land: land)
                }
            }
        }
    }

    // MARK: - Reusable subviews

    @ViewBuilder
    private func insightTile(
        title: String,
        value: String,
        subtitle: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(tint)
            Text(title)
                .font(.poppins(.caption, .semibold))
                .foregroundStyle(AppTheme.inkSecondary)
                .lineLimit(1)
            Text(value)
                .font(.poppins(size: 18, .bold, relativeTo: .headline))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Text(subtitle)
                .font(.poppins(.caption2))
                .foregroundStyle(AppTheme.inkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func landHighlightTile(label: String, land: Land, tint: Color) -> some View {
        let insight = LandEconomicInsight(land: land)
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.poppins(.caption, .semibold))
                .foregroundStyle(tint)
            Text(land.name)
                .font(.poppins(.subheadline, .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(insight.netMarginRate.map {
                "\(($0 * 100).formatted(.number.precision(.fractionLength(1))))%"
            } ?? "—")
                .font(.poppins(.caption))
                .foregroundStyle(AppTheme.inkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func suggestionRow(land: Land, suggestion: LandSuggestion) -> some View {
        let (icon, detail, tint) = suggestionContent(suggestion)
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(land.name)
                    .font(.poppins(.subheadline, .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.poppins(.caption))
                    .foregroundStyle(AppTheme.inkSecondary)
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
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func landBreakdownRow(land: Land) -> some View {
        let insight = LandEconomicInsight(land: land)
        let margin = insight.netMarginRate ?? 0
        let tint: Color = margin >= 0
            ? AppTheme.positive
            : AppTheme.negative
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(land.name)
                    .font(.poppins(.subheadline, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(land.annualNetMargin.formatted(.currency(code: currencyCode)))
                    .font(.poppins(.caption))
                    .foregroundStyle(AppTheme.inkSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(insight.netMarginRate.map {
                    "\(($0 * 100).formatted(.number.precision(.fractionLength(1))))%"
                } ?? "—")
                    .font(.poppins(.subheadline, .bold))
                    .foregroundStyle(tint)
                if let perAcre = insight.incomePerAcre {
                    Text("\(perAcre.formatted(.currency(code: currencyCode)))/\(AppSettings.areaShortUnit(system: measurementSystem))")
                        .font(.poppins(.caption2))
                        .foregroundStyle(AppTheme.inkSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
    }

    // MARK: - Empty states

    private var ownerOnlyPlaceholder: some View {
        ContentUnavailableView(
            language.localized("Owner Access Required", "Acceso de propietario requerido"),
            systemImage: "lock.shield",
            description: Text(language.localized(
                "Economic insights are only visible to the account owner.",
                "Los análisis económicos solo son visibles para el propietario de la cuenta."
            ))
        )
    }

    private var emptyState: some View {
        ContentUnavailableView(
            language.localized("No Lands Yet", "Aún no hay terrenos"),
            systemImage: "chart.bar",
            description: Text(language.localized(
                "Add your first land to start seeing economic insights.",
                "Añade tu primer terreno para empezar a ver los análisis económicos."
            ))
        )
    }

    // MARK: - Helpers

    private func suggestionContent(_ suggestion: LandSuggestion) -> (String, String, Color) {
        switch suggestion {
        case .negativeMargin(let amount):
            return (
                "exclamationmark.triangle.fill",
                language.localized(
                    "Losing \((-amount).formatted(.currency(code: currencyCode))) per year based on your plan.",
                    "Pérdida de \((-amount).formatted(.currency(code: currencyCode))) anuales según tu plan."
                ),
                AppTheme.negative
            )
        case .dominantCost(let category, let share):
            return (
                "chart.pie.fill",
                language.localized(
                    "\(category.rawValue.capitalized) accounts for \((share * 100).formatted(.number.precision(.fractionLength(0))))% of total expenses.",
                    "\(category.rawValue.capitalized) representa el \((share * 100).formatted(.number.precision(.fractionLength(0))))% del gasto total."
                ),
                AppTheme.warning
            )
        case .planUnderachieved(let variance):
            return (
                "arrow.down.circle.fill",
                language.localized(
                    "\((-variance).formatted(.currency(code: currencyCode))) below prorated plan based on months recorded.",
                    "\((-variance).formatted(.currency(code: currencyCode))) por debajo del plan prorrateado según los meses registrados."
                ),
                AppTheme.clay
            )
        case .noHistoryData:
            return (
                "calendar.badge.exclamationmark",
                language.localized(
                    "No monthly history recorded. Add actuals to unlock trend analysis.",
                    "Sin histórico mensual registrado. Añade datos reales para activar el análisis de tendencia."
                ),
                AppTheme.highlight
            )
        }
    }

    private var twoColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }
}

// MARK: - Preview

#Preview {
    UserDefaults.standard.set(AppAccessRole.owner.rawValue, forKey: "access.activeRole")

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Land.self, LandHistoryEntry.self, LandGroup.self, LandTask.self,
        configurations: config
    )
    let ctx = container.mainContext

    let land1 = Land(
        name: "Finca El Olivo",
        latitude: 37.39, longitude: -5.99,
        sizeAcres: 12.5,
        productionType: ProductionCatalog.oliveGrove,
        productionSubtype: "Picual",
        incomeAnnual: 28000,
        annualIrrigationCost: 3200,
        annualFertilizerCost: 1800,
        annualLaborCost: 8500,
        annualMaintenanceCost: 1200,
        notes: ""
    )
    ctx.insert(land1)

    let land2 = Land(
        name: "Viña Norte",
        latitude: 37.50, longitude: -5.80,
        sizeAcres: 8.0,
        productionType: ProductionCatalog.vineyard,
        productionSubtype: "Tempranillo",
        incomeAnnual: 14000,
        annualIrrigationCost: 2100,
        annualFertilizerCost: 900,
        annualLaborCost: 12000,
        annualMaintenanceCost: 800,
        notes: ""
    )
    ctx.insert(land2)

    let currentYear = Calendar.current.component(.year, from: Date())
    let incomes = [2100.0, 1950.0, 2300.0, 2050.0, 1800.0, 2200.0, 2400.0, 1750.0]
    for (i, income) in incomes.enumerated() {
        let entry = LandHistoryEntry(
            year: currentYear,
            month: i + 1,
            incomeAmount: income,
            productionAmount: 280,
            electricityKWh: 0,
            land: land1
        )
        ctx.insert(entry)
    }

    return NavigationStack {
        InsightsView()
    }
    .modelContainer(container)
    .environmentObject(RoleAccessViewModel())
}
