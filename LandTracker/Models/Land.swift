import Foundation
import SwiftData
import CoreLocation

@Model
final class Land {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var sizeAcres: Double
    var activityType: String = ActivityCatalog.defaultName
    var productionType: String
    var incomeAnnual: Double
    var annualIrrigationCost: Double = 0
    var annualFertilizerCost: Double = 0
    var annualLaborCost: Double = 0
    var annualMaintenanceCost: Double = 0
    var notes: String
    var installedCapacityKW: Double = 0
    var annualElectricityProductionKWh: Double = 0
    var selfConsumptionRate: Double = 0
    var gridExportRate: Double = 0
    var createdAt: Date
    var updatedAt: Date
    var catastroRefcat14: String?
    var catastroAreaValue: Double?
    var catastroAreaUom: String?
    var catastroLabel: String?
    var catastroRingsData: Data = Data()
    var catastroFetchedAt: Date?
    var devicesData: Data = Data()
    var group: LandGroup?
    var productionSubtype: String = ""
    @Relationship(deleteRule: .cascade, inverse: \LandHistoryEntry.land) var historyEntries: [LandHistoryEntry] = []
    @Relationship(deleteRule: .cascade, inverse: \LandTask.land) var tasks: [LandTask] = []

    init(
        name: String,
        latitude: Double,
        longitude: Double,
        sizeAcres: Double,
        activityType: String = ActivityCatalog.defaultName,
        productionType: String,
        productionSubtype: String,
        incomeAnnual: Double,
        annualIrrigationCost: Double = 0,
        annualFertilizerCost: Double = 0,
        annualLaborCost: Double = 0,
        annualMaintenanceCost: Double = 0,
        notes: String,
        installedCapacityKW: Double = 0,
        annualElectricityProductionKWh: Double = 0,
        selfConsumptionRate: Double = 0,
        gridExportRate: Double = 0,
        catastroRefcat14: String? = nil,
        catastroAreaValue: Double? = nil,
        catastroAreaUom: String? = nil,
        catastroLabel: String? = nil,
        catastroRings: [[Coordinate]] = [],
        catastroFetchedAt: Date? = nil,
        devices: [LandDevice] = [],
        group: LandGroup? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.sizeAcres = sizeAcres
        self.activityType = activityType
        self.productionType = productionType
        self.productionSubtype = productionSubtype
        self.incomeAnnual = incomeAnnual
        self.annualIrrigationCost = annualIrrigationCost
        self.annualFertilizerCost = annualFertilizerCost
        self.annualLaborCost = annualLaborCost
        self.annualMaintenanceCost = annualMaintenanceCost
        self.notes = notes
        self.installedCapacityKW = installedCapacityKW
        self.annualElectricityProductionKWh = annualElectricityProductionKWh
        self.selfConsumptionRate = selfConsumptionRate
        self.gridExportRate = gridExportRate
        self.createdAt = Date()
        self.updatedAt = Date()
        self.catastroRefcat14 = catastroRefcat14
        self.catastroAreaValue = catastroAreaValue
        self.catastroAreaUom = catastroAreaUom
        self.catastroLabel = catastroLabel
        self.catastroRingsData = Self.encodeRings(catastroRings)
        self.catastroFetchedAt = catastroFetchedAt
        self.devicesData = Self.encodeDevices(devices)
        self.group = group
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var locationText: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    var annualTotalExpenses: Double {
        max(0, annualIrrigationCost) +
        max(0, annualFertilizerCost) +
        max(0, annualLaborCost) +
        max(0, annualMaintenanceCost)
    }

    var annualNetMargin: Double {
        incomeAnnual - annualTotalExpenses
    }

    func touchUpdatedAt() {
        updatedAt = Date()
    }

    var catastroRings: [[Coordinate]] {
        get {
            Self.decodeRings(catastroRingsData)
        }
        set {
            catastroRingsData = Self.encodeRings(newValue)
        }
    }

    var devices: [LandDevice] {
        get {
            Self.decodeDevices(devicesData)
        }
        set {
            devicesData = Self.encodeDevices(newValue)
        }
    }

    private static func encodeRings(_ rings: [[Coordinate]]) -> Data {
        (try? JSONEncoder().encode(rings)) ?? Data()
    }

    private static func decodeRings(_ data: Data) -> [[Coordinate]] {
        (try? JSONDecoder().decode([[Coordinate]].self, from: data)) ?? []
    }

    private static func encodeDevices(_ devices: [LandDevice]) -> Data {
        (try? JSONEncoder().encode(devices)) ?? Data()
    }

    private static func decodeDevices(_ data: Data) -> [LandDevice] {
        (try? JSONDecoder().decode([LandDevice].self, from: data)) ?? []
    }
}

struct Coordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
