import SwiftUI
import SwiftData

struct ExpenseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @AppStorage(AccountPreferences.preferredCurrencyCodeKey) private var preferredCurrencyCode = AppSettings.defaultCurrency.rawValue

    let land: Land

    @State private var irrigationCost: Double
    @State private var fertilizerCost: Double
    @State private var laborCost: Double
    @State private var maintenanceCost: Double

    init(land: Land) {
        self.land = land
        _irrigationCost = State(initialValue: max(0, land.annualIrrigationCost))
        _fertilizerCost = State(initialValue: max(0, land.annualFertilizerCost))
        _laborCost = State(initialValue: max(0, land.annualLaborCost))
        _maintenanceCost = State(initialValue: max(0, land.annualMaintenanceCost))
    }

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var currencyCode: String {
        AppSettings.currencyCode(from: preferredCurrencyCode)
    }

    private var totalExpenses: Double {
        max(0, irrigationCost) + max(0, fertilizerCost) + max(0, laborCost) + max(0, maintenanceCost)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(language.localized("Irrigation", "Riego"), value: $irrigationCost, format: .currency(code: currencyCode))
                        .keyboardType(.decimalPad)
                    TextField(language.localized("Fertilizer", "Fertilizantes"), value: $fertilizerCost, format: .currency(code: currencyCode))
                        .keyboardType(.decimalPad)
                    TextField(language.localized("Labor", "Mano de obra"), value: $laborCost, format: .currency(code: currencyCode))
                        .keyboardType(.decimalPad)
                    TextField(language.localized("Maintenance", "Mantenimiento"), value: $maintenanceCost, format: .currency(code: currencyCode))
                        .keyboardType(.decimalPad)

                    LabeledContent(language.localized("Total", "Total")) {
                        Text(totalExpenses, format: .currency(code: currencyCode))
                            .foregroundStyle(AppTheme.inkSecondary)
                    }
                } header: {
                    AppSectionHeader(language.localized("Annual Expenses", "Gastos anuales"))
                }
                .listRowBackground(AppTheme.card)
            }
            .font(.poppins(.body))
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(language.localized("Update Expenses", "Actualizar gastos"))
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
                }
            }
        }
    }

    private func save() {
        land.annualIrrigationCost = max(0, irrigationCost)
        land.annualFertilizerCost = max(0, fertilizerCost)
        land.annualLaborCost = max(0, laborCost)
        land.annualMaintenanceCost = max(0, maintenanceCost)
        land.touchUpdatedAt()

        try? context.save()
        Task { @MainActor in
            await SupabaseSyncService.shared.queueLandUpsert(id: land.id, context: context)
        }
        dismiss()
    }
}
