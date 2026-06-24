import Foundation
import SwiftData

enum LandHistorySource: String, Codable, CaseIterable {
    case manual
    case spreadsheet
}

@Model
final class LandHistoryEntry {
    var id: UUID
    var year: Int
    var month: Int
    var incomeAmount: Double
    var productionAmount: Double
    var productionUnit: String
    var electricityKWh: Double
    var notes: String
    var sourceRaw: String = LandHistorySource.manual.rawValue
    var createdAt: Date
    var updatedAt: Date
    var land: Land?

    init(
        year: Int,
        month: Int,
        incomeAmount: Double,
        productionAmount: Double,
        productionUnit: String = "t",
        electricityKWh: Double,
        notes: String = "",
        source: LandHistorySource = .manual,
        land: Land? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.year = year
        self.month = month
        self.incomeAmount = incomeAmount
        self.productionAmount = productionAmount
        self.productionUnit = productionUnit
        self.electricityKWh = electricityKWh
        self.notes = notes
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.land = land
    }

    var periodDate: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }

    var periodKey: Int {
        year * 100 + month
    }

    var source: LandHistorySource {
        get { LandHistorySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    func touchUpdatedAt() {
        updatedAt = Date()
    }
}
