import Foundation
import SwiftData

struct ExportData: Codable {
    var version: Int
    var exportedAt: Date
    var groups: [GroupSnapshot]
    var lands: [LandSnapshot]
    var history: [LandHistorySnapshot]?
    var tasks: [LandTaskSnapshot]?
}

struct GroupSnapshot: Codable {
    var id: UUID
    var name: String
    var colorHex: String
}

struct LandSnapshot: Codable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var sizeAcres: Double
    var activityType: String?
    var productionType: String
    var productionSubtype: String?
    var incomeAnnual: Double
    var annualIrrigationCost: Double?
    var annualFertilizerCost: Double?
    var annualLaborCost: Double?
    var annualMaintenanceCost: Double?
    var notes: String
    var installedCapacityKW: Double?
    var annualElectricityProductionKWh: Double?
    var selfConsumptionRate: Double?
    var gridExportRate: Double?
    var catastroRefcat14: String?
    var catastroAreaValue: Double?
    var catastroAreaUom: String?
    var catastroLabel: String?
    var catastroRings: [[Coordinate]]
    var catastroFetchedAt: Date?
    var devices: [LandDevice]?
    var groupId: UUID?
}

struct LandHistorySnapshot: Codable {
    var id: UUID
    var landId: UUID
    var year: Int
    var month: Int
    var incomeAmount: Double
    var productionAmount: Double
    var productionUnit: String
    var electricityKWh: Double
    var notes: String
    var sourceRaw: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct LandTaskSnapshot: Codable {
    var id: UUID
    var landId: UUID
    var typeRaw: String?
    var title: String
    var dueDate: Date
    var reminderDate: Date?
    var notes: String?
    var isCompleted: Bool?
    var completedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
}

enum ImportExportError: Error, LocalizedError {
    case decodeFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .decodeFailed:
            return "Could not read this file."
        case .encodeFailed:
            return "Could not create export file."
        }
    }
}

final class ImportExportService {
    static func exportData(lands: [Land], groups: [LandGroup]) throws -> Data {
        let groupSnapshots = groups.map { GroupSnapshot(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        let landSnapshots = lands.map { land in
            LandSnapshot(
                id: land.id,
                name: land.name,
                latitude: land.latitude,
                longitude: land.longitude,
                sizeAcres: land.sizeAcres,
                activityType: land.activityType,
                productionType: land.productionType,
                productionSubtype: land.productionSubtype,
                incomeAnnual: land.incomeAnnual,
                annualIrrigationCost: land.annualIrrigationCost,
                annualFertilizerCost: land.annualFertilizerCost,
                annualLaborCost: land.annualLaborCost,
                annualMaintenanceCost: land.annualMaintenanceCost,
                notes: land.notes,
                installedCapacityKW: land.installedCapacityKW,
                annualElectricityProductionKWh: land.annualElectricityProductionKWh,
                selfConsumptionRate: land.selfConsumptionRate,
                gridExportRate: land.gridExportRate,
                catastroRefcat14: land.catastroRefcat14,
                catastroAreaValue: land.catastroAreaValue,
                catastroAreaUom: land.catastroAreaUom,
                catastroLabel: land.catastroLabel,
                catastroRings: land.catastroRings,
                catastroFetchedAt: land.catastroFetchedAt,
                devices: land.devices,
                groupId: land.group?.id
            )
        }

        let historySnapshots = lands
            .flatMap { land in
                land.historyEntries.map { entry in
                    LandHistorySnapshot(
                        id: entry.id,
                        landId: land.id,
                        year: entry.year,
                        month: entry.month,
                        incomeAmount: entry.incomeAmount,
                        productionAmount: entry.productionAmount,
                        productionUnit: entry.productionUnit,
                        electricityKWh: entry.electricityKWh,
                        notes: entry.notes,
                        sourceRaw: entry.source.rawValue,
                        createdAt: entry.createdAt,
                        updatedAt: entry.updatedAt
                    )
                }
            }

        let taskSnapshots = lands
            .flatMap { land in
                land.tasks.map { task in
                    LandTaskSnapshot(
                        id: task.id,
                        landId: land.id,
                        typeRaw: task.type.rawValue,
                        title: task.title,
                        dueDate: task.dueDate,
                        reminderDate: task.reminderDate,
                        notes: task.notes,
                        isCompleted: task.isCompleted,
                        completedAt: task.completedAt,
                        createdAt: task.createdAt,
                        updatedAt: task.updatedAt
                    )
                }
            }

        let export = ExportData(
            version: 6,
            exportedAt: Date(),
            groups: groupSnapshots,
            lands: landSnapshots,
            history: historySnapshots,
            tasks: taskSnapshots
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(export) else {
            throw ImportExportError.encodeFailed
        }
        return data
    }

    static func importData(_ data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let export = try? decoder.decode(ExportData.self, from: data) else {
            throw ImportExportError.decodeFailed
        }

        var groupById: [UUID: LandGroup] = [:]
        let existingGroups = try? context.fetch(FetchDescriptor<LandGroup>())
        existingGroups?.forEach { groupById[$0.id] = $0 }

        for snapshot in export.groups {
            if let existing = groupById[snapshot.id] {
                existing.name = snapshot.name
                existing.colorHex = snapshot.colorHex
            } else {
                let group = LandGroup(name: snapshot.name, colorHex: snapshot.colorHex)
                group.id = snapshot.id
                context.insert(group)
                groupById[snapshot.id] = group
            }
        }

        var landById: [UUID: Land] = [:]
        let existingLands = try? context.fetch(FetchDescriptor<Land>())
        existingLands?.forEach { landById[$0.id] = $0 }

        for snapshot in export.lands {
            let group = snapshot.groupId.flatMap { groupById[$0] }
            if let existing = landById[snapshot.id] {
                existing.name = snapshot.name
                existing.latitude = snapshot.latitude
                existing.longitude = snapshot.longitude
                existing.sizeAcres = snapshot.sizeAcres
                existing.activityType = snapshot.activityType ?? ActivityCatalog.defaultName
                existing.productionType = snapshot.productionType
                existing.productionSubtype = snapshot.productionSubtype ?? ""
                existing.incomeAnnual = snapshot.incomeAnnual
                existing.annualIrrigationCost = snapshot.annualIrrigationCost ?? 0
                existing.annualFertilizerCost = snapshot.annualFertilizerCost ?? 0
                existing.annualLaborCost = snapshot.annualLaborCost ?? 0
                existing.annualMaintenanceCost = snapshot.annualMaintenanceCost ?? 0
                existing.notes = snapshot.notes
                existing.installedCapacityKW = snapshot.installedCapacityKW ?? 0
                existing.annualElectricityProductionKWh = snapshot.annualElectricityProductionKWh ?? 0
                existing.selfConsumptionRate = snapshot.selfConsumptionRate ?? 0
                existing.gridExportRate = snapshot.gridExportRate ?? 0
                existing.catastroRefcat14 = snapshot.catastroRefcat14
                existing.catastroAreaValue = snapshot.catastroAreaValue
                existing.catastroAreaUom = snapshot.catastroAreaUom
                existing.catastroLabel = snapshot.catastroLabel
                existing.catastroRings = snapshot.catastroRings
                existing.catastroFetchedAt = snapshot.catastroFetchedAt
                existing.devices = snapshot.devices ?? []
                existing.group = group
                existing.touchUpdatedAt()
            } else {
                let land = Land(
                    name: snapshot.name,
                    latitude: snapshot.latitude,
                    longitude: snapshot.longitude,
                    sizeAcres: snapshot.sizeAcres,
                    activityType: snapshot.activityType ?? ActivityCatalog.defaultName,
                    productionType: snapshot.productionType,
                    productionSubtype: snapshot.productionSubtype ?? "",
                    incomeAnnual: snapshot.incomeAnnual,
                    annualIrrigationCost: snapshot.annualIrrigationCost ?? 0,
                    annualFertilizerCost: snapshot.annualFertilizerCost ?? 0,
                    annualLaborCost: snapshot.annualLaborCost ?? 0,
                    annualMaintenanceCost: snapshot.annualMaintenanceCost ?? 0,
                    notes: snapshot.notes,
                    installedCapacityKW: snapshot.installedCapacityKW ?? 0,
                    annualElectricityProductionKWh: snapshot.annualElectricityProductionKWh ?? 0,
                    selfConsumptionRate: snapshot.selfConsumptionRate ?? 0,
                    gridExportRate: snapshot.gridExportRate ?? 0,
                    catastroRefcat14: snapshot.catastroRefcat14,
                    catastroAreaValue: snapshot.catastroAreaValue,
                    catastroAreaUom: snapshot.catastroAreaUom,
                    catastroLabel: snapshot.catastroLabel,
                    catastroRings: snapshot.catastroRings,
                    catastroFetchedAt: snapshot.catastroFetchedAt,
                    devices: snapshot.devices ?? [],
                    group: group
                )
                land.id = snapshot.id
                context.insert(land)
                landById[snapshot.id] = land
            }
        }

        var historyById: [UUID: LandHistoryEntry] = [:]
        let existingHistory = try? context.fetch(FetchDescriptor<LandHistoryEntry>())
        existingHistory?.forEach { historyById[$0.id] = $0 }

        for snapshot in (export.history ?? []) {
            guard let land = landById[snapshot.landId] else { continue }

            if let existing = historyById[snapshot.id] {
                existing.year = snapshot.year
                existing.month = snapshot.month
                existing.incomeAmount = snapshot.incomeAmount
                existing.productionAmount = snapshot.productionAmount
                existing.productionUnit = snapshot.productionUnit
                existing.electricityKWh = snapshot.electricityKWh
                existing.notes = snapshot.notes
                existing.source = LandHistorySource(rawValue: snapshot.sourceRaw ?? "") ?? .manual
                existing.land = land
                if let createdAt = snapshot.createdAt {
                    existing.createdAt = createdAt
                }
                existing.updatedAt = snapshot.updatedAt ?? Date()
            } else {
                let entry = LandHistoryEntry(
                    year: snapshot.year,
                    month: snapshot.month,
                    incomeAmount: snapshot.incomeAmount,
                    productionAmount: snapshot.productionAmount,
                    productionUnit: snapshot.productionUnit,
                    electricityKWh: snapshot.electricityKWh,
                    notes: snapshot.notes,
                    source: LandHistorySource(rawValue: snapshot.sourceRaw ?? "") ?? .manual,
                    land: land,
                    createdAt: snapshot.createdAt ?? Date()
                )
                entry.id = snapshot.id
                entry.updatedAt = snapshot.updatedAt ?? Date()
                context.insert(entry)
                historyById[snapshot.id] = entry
            }
        }

        var tasksByID: [UUID: LandTask] = [:]
        let existingTasks = try? context.fetch(FetchDescriptor<LandTask>())
        existingTasks?.forEach { tasksByID[$0.id] = $0 }

        for snapshot in (export.tasks ?? []) {
            guard let land = landById[snapshot.landId] else { continue }

            let resolvedType = LandTaskType(rawValue: snapshot.typeRaw ?? "") ?? .other
            let resolvedNotes = snapshot.notes ?? ""
            let resolvedIsCompleted = snapshot.isCompleted ?? false
            let resolvedCompletedAt = resolvedIsCompleted ? snapshot.completedAt : nil

            if let existing = tasksByID[snapshot.id] {
                existing.type = resolvedType
                existing.title = snapshot.title
                existing.dueDate = snapshot.dueDate
                existing.reminderDate = snapshot.reminderDate
                existing.notes = resolvedNotes
                existing.isCompleted = resolvedIsCompleted
                existing.completedAt = resolvedCompletedAt
                existing.land = land
                if let createdAt = snapshot.createdAt {
                    existing.createdAt = createdAt
                }
                existing.updatedAt = snapshot.updatedAt ?? Date()
            } else {
                let task = LandTask(
                    type: resolvedType,
                    title: snapshot.title,
                    dueDate: snapshot.dueDate,
                    reminderDate: snapshot.reminderDate,
                    notes: resolvedNotes,
                    isCompleted: resolvedIsCompleted,
                    completedAt: resolvedCompletedAt,
                    land: land,
                    createdAt: snapshot.createdAt ?? Date()
                )
                task.id = snapshot.id
                task.updatedAt = snapshot.updatedAt ?? Date()
                context.insert(task)
                tasksByID[snapshot.id] = task
            }
        }
    }
}
