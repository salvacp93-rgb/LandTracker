import SwiftUI
import SwiftData

struct HistoryEntryEditorView: View {
    enum Mode {
        case create(Land)
        case edit(LandHistoryEntry)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @AppStorage(AccountPreferences.preferredCurrencyCodeKey) private var preferredCurrencyCode = AppSettings.defaultCurrency.rawValue

    private let mode: Mode

    @State private var year: Int
    @State private var month: Int
    @State private var incomeAmount: Double
    @State private var productionAmount: Double
    @State private var productionUnit: String
    @State private var electricityKWh: Double
    @State private var notes: String

    private static let monthNames: [String] = {
        let formatter = DateFormatter()
        return formatter.monthSymbols ?? [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
    }()

    init(mode: Mode) {
        self.mode = mode
        let currentDate = Date()
        let calendar = Calendar.current

        switch mode {
        case .create:
            _year = State(initialValue: calendar.component(.year, from: currentDate))
            _month = State(initialValue: calendar.component(.month, from: currentDate))
            _incomeAmount = State(initialValue: 0)
            _productionAmount = State(initialValue: 0)
            _productionUnit = State(initialValue: "t")
            _electricityKWh = State(initialValue: 0)
            _notes = State(initialValue: "")
        case .edit(let entry):
            _year = State(initialValue: entry.year)
            _month = State(initialValue: entry.month)
            _incomeAmount = State(initialValue: entry.incomeAmount)
            _productionAmount = State(initialValue: entry.productionAmount)
            _productionUnit = State(initialValue: entry.productionUnit)
            _electricityKWh = State(initialValue: entry.electricityKWh)
            _notes = State(initialValue: entry.notes)
        }
    }

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var currencyCode: String {
        AppSettings.currencyCode(from: preferredCurrencyCode)
    }

    private var title: String {
        switch mode {
        case .create:
            return language.localized("New Record", "Nuevo registro")
        case .edit:
            return language.localized("Edit Record", "Editar registro")
        }
    }

    private var canSave: Bool {
        (1...12).contains(month) &&
        (2000...2100).contains(year) &&
        !productionUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section(language.localized("Period", "Periodo")) {
                Picker(language.localized("Month", "Mes"), selection: $month) {
                    ForEach(1...12, id: \.self) { value in
                        Text(Self.monthNames[value - 1]).tag(value)
                    }
                }

                Stepper(value: $year, in: 2000...2100) {
                    Text("\(language.localized("Year", "Año")): \(year)")
                }
            }

            Section(language.localized("Metrics", "Métricas")) {
                TextField(language.localized("Income", "Ingresos"), value: $incomeAmount, format: .currency(code: currencyCode))
                    .keyboardType(.decimalPad)

                TextField(language.localized("Production", "Producción"), value: $productionAmount, format: .number)
                    .keyboardType(.decimalPad)

                TextField(language.localized("Production Unit", "Unidad de producción"), text: $productionUnit)

                TextField(language.localized("Electricity (kWh)", "Electricidad (kWh)"), value: $electricityKWh, format: .number)
                    .keyboardType(.decimalPad)
            }

            Section(language.localized("Notes", "Notas")) {
                TextEditor(text: $notes)
                    .frame(minHeight: 110)
            }
        }
        .navigationTitle(title)
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

    private func save() {
        let safeYear = min(2100, max(2000, year))
        let safeMonth = min(12, max(1, month))
        let safeIncome = max(0, incomeAmount)
        let safeProduction = max(0, productionAmount)
        let safeElectricity = max(0, electricityKWh)
        let safeUnit = productionUnit.trimmingCharacters(in: .whitespacesAndNewlines)

        var entryID: UUID?
        var landID: UUID?

        switch mode {
        case .create(let land):
            let entry = LandHistoryEntry(
                year: safeYear,
                month: safeMonth,
                incomeAmount: safeIncome,
                productionAmount: safeProduction,
                productionUnit: safeUnit.isEmpty ? "t" : safeUnit,
                electricityKWh: safeElectricity,
                notes: notes,
                source: .manual,
                land: land
            )
            context.insert(entry)
            land.touchUpdatedAt()
            entryID = entry.id
            landID = land.id

        case .edit(let entry):
            entry.year = safeYear
            entry.month = safeMonth
            entry.incomeAmount = safeIncome
            entry.productionAmount = safeProduction
            entry.productionUnit = safeUnit.isEmpty ? "t" : safeUnit
            entry.electricityKWh = safeElectricity
            entry.notes = notes
            entry.touchUpdatedAt()
            if let land = entry.land {
                land.touchUpdatedAt()
                landID = land.id
            }
            entryID = entry.source == .manual ? entry.id : nil
        }

        try? context.save()

        if let entryID {
            Task { @MainActor in
                await SupabaseSyncService.shared.queueHistoryEntryUpsert(id: entryID, context: context)
                if let landID {
                    await SupabaseSyncService.shared.queueLandUpsert(id: landID, context: context)
                }
            }
        }

        dismiss()
    }
}
