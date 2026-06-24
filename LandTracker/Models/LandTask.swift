import Foundation
import SwiftData

enum LandTaskType: String, Codable, CaseIterable, Identifiable {
    case irrigation
    case pruning
    case harvest
    case panelMaintenance
    case inverterMaintenance
    case other

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .irrigation:
            return language.localized("Irrigation", "Riego")
        case .pruning:
            return language.localized("Pruning", "Poda")
        case .harvest:
            return language.localized("Harvest", "Cosecha")
        case .panelMaintenance:
            return language.localized("Panel Maintenance", "Mantenimiento de paneles")
        case .inverterMaintenance:
            return language.localized("Inverter Maintenance", "Mantenimiento de inversor")
        case .other:
            return language.localized("Other", "Otra")
        }
    }

    var symbolName: String {
        switch self {
        case .irrigation:
            return "drop.fill"
        case .pruning:
            return "scissors"
        case .harvest:
            return "basket.fill"
        case .panelMaintenance:
            return "solarpanel"
        case .inverterMaintenance:
            return "bolt.fill"
        case .other:
            return "checklist"
        }
    }
}

@Model
final class LandTask {
    var id: UUID
    var typeRaw: String
    var title: String
    var dueDate: Date
    var reminderDate: Date?
    var notes: String
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var land: Land?

    init(
        type: LandTaskType,
        title: String,
        dueDate: Date,
        reminderDate: Date? = nil,
        notes: String = "",
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        land: Land? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.title = title
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.notes = notes
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.land = land
    }

    var type: LandTaskType {
        get { LandTaskType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    func markCompleted(at date: Date = Date()) {
        isCompleted = true
        completedAt = date
        updatedAt = date
    }

    func reopen(at date: Date = Date()) {
        isCompleted = false
        completedAt = nil
        updatedAt = date
    }

    func touchUpdatedAt() {
        updatedAt = Date()
    }
}
