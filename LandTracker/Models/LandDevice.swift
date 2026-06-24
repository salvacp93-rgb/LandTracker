import Foundation

enum LandDeviceType: String, Codable, CaseIterable, Identifiable {
    case thermometer
    case waterPump
    case rainGauge
    case humiditySensor
    case pressureSensor
    case energyMeter
    case inverter
    case other

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .thermometer:
            return language.localized("Thermometer", "Termómetro")
        case .waterPump:
            return language.localized("Water Pump", "Bomba de agua")
        case .rainGauge:
            return language.localized("Rain Gauge", "Pluviómetro")
        case .humiditySensor:
            return language.localized("Humidity Sensor", "Sensor de humedad")
        case .pressureSensor:
            return language.localized("Pressure Sensor", "Sensor de presión")
        case .energyMeter:
            return language.localized("Energy Meter", "Contador energético")
        case .inverter:
            return language.localized("Inverter", "Inversor")
        case .other:
            return language.localized("Other", "Otro")
        }
    }

    var symbolName: String {
        switch self {
        case .thermometer:
            return "thermometer.medium"
        case .waterPump:
            return "drop.circle.fill"
        case .rainGauge:
            return "cloud.rain.fill"
        case .humiditySensor:
            return "humidity.fill"
        case .pressureSensor:
            return "gauge.with.dots.needle.33percent"
        case .energyMeter:
            return "bolt.circle.fill"
        case .inverter:
            return "bolt.horizontal.circle.fill"
        case .other:
            return "sensor.tag.radiowaves.forward.fill"
        }
    }
}

enum LandDeviceLinkMethod: String, Codable, CaseIterable, Identifiable {
    case bluetooth
    case cloudAPI = "cloud_api"
    case mqttGateway = "mqtt_gateway"
    case manual

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .bluetooth:
            return language.localized("Bluetooth", "Bluetooth")
        case .cloudAPI:
            return language.localized("Cloud API", "API en la nube")
        case .mqttGateway:
            return language.localized("MQTT Gateway", "Pasarela MQTT")
        case .manual:
            return language.localized("Manual", "Manual")
        }
    }

    var symbolName: String {
        switch self {
        case .bluetooth:
            return "dot.radiowaves.left.and.right"
        case .cloudAPI:
            return "cloud.fill"
        case .mqttGateway:
            return "antenna.radiowaves.left.and.right"
        case .manual:
            return "hand.tap.fill"
        }
    }
}

enum LandDeviceLinkState: String, Codable, CaseIterable {
    case unlinked
    case linking
    case linked
    case error
}

struct LandDevice: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var typeRaw: String
    var manufacturer: String
    var model: String
    var serialNumber: String
    var metricName: String
    var metricUnit: String
    var lastReadingValue: Double?
    var batteryLevel: Double?
    var installedAt: Date
    var lastSeenAt: Date?
    var isActive: Bool
    var notes: String
    var linkMethodRaw: String
    var linkStateRaw: String
    var telemetryIntervalSeconds: Int

    init(
        id: UUID = UUID(),
        name: String,
        type: LandDeviceType,
        manufacturer: String = "",
        model: String = "",
        serialNumber: String = "",
        metricName: String = "",
        metricUnit: String = "",
        lastReadingValue: Double? = nil,
        batteryLevel: Double? = nil,
        installedAt: Date = Date(),
        lastSeenAt: Date? = nil,
        isActive: Bool = true,
        notes: String = "",
        linkMethod: LandDeviceLinkMethod = .manual,
        linkState: LandDeviceLinkState = .linked,
        telemetryIntervalSeconds: Int = 300
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.manufacturer = manufacturer
        self.model = model
        self.serialNumber = serialNumber
        self.metricName = metricName
        self.metricUnit = metricUnit
        self.lastReadingValue = lastReadingValue
        self.batteryLevel = batteryLevel
        self.installedAt = installedAt
        self.lastSeenAt = lastSeenAt
        self.isActive = isActive
        self.notes = notes
        self.linkMethodRaw = linkMethod.rawValue
        self.linkStateRaw = linkState.rawValue
        self.telemetryIntervalSeconds = max(30, telemetryIntervalSeconds)
    }

    var type: LandDeviceType {
        get { LandDeviceType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var linkMethod: LandDeviceLinkMethod {
        get { LandDeviceLinkMethod(rawValue: linkMethodRaw) ?? .manual }
        set { linkMethodRaw = newValue.rawValue }
    }

    var linkState: LandDeviceLinkState {
        get { LandDeviceLinkState(rawValue: linkStateRaw) ?? .linked }
        set { linkStateRaw = newValue.rawValue }
    }

    var telemetryIntervalMinutes: Int {
        max(1, telemetryIntervalSeconds / 60)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case typeRaw
        case manufacturer
        case model
        case serialNumber
        case metricName
        case metricUnit
        case lastReadingValue
        case batteryLevel
        case installedAt
        case lastSeenAt
        case isActive
        case notes
        case linkMethodRaw
        case linkStateRaw
        case telemetryIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        typeRaw = try container.decodeIfPresent(String.self, forKey: .typeRaw) ?? LandDeviceType.other.rawValue
        manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber) ?? ""
        metricName = try container.decodeIfPresent(String.self, forKey: .metricName) ?? ""
        metricUnit = try container.decodeIfPresent(String.self, forKey: .metricUnit) ?? ""
        lastReadingValue = try container.decodeIfPresent(Double.self, forKey: .lastReadingValue)
        batteryLevel = try container.decodeIfPresent(Double.self, forKey: .batteryLevel)
        installedAt = try container.decodeIfPresent(Date.self, forKey: .installedAt) ?? Date()
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        linkMethodRaw = try container.decodeIfPresent(String.self, forKey: .linkMethodRaw) ?? LandDeviceLinkMethod.manual.rawValue
        linkStateRaw = try container.decodeIfPresent(String.self, forKey: .linkStateRaw) ?? LandDeviceLinkState.linked.rawValue
        telemetryIntervalSeconds = max(30, try container.decodeIfPresent(Int.self, forKey: .telemetryIntervalSeconds) ?? 300)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(typeRaw, forKey: .typeRaw)
        try container.encode(manufacturer, forKey: .manufacturer)
        try container.encode(model, forKey: .model)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encode(metricName, forKey: .metricName)
        try container.encode(metricUnit, forKey: .metricUnit)
        try container.encodeIfPresent(lastReadingValue, forKey: .lastReadingValue)
        try container.encodeIfPresent(batteryLevel, forKey: .batteryLevel)
        try container.encode(installedAt, forKey: .installedAt)
        try container.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(notes, forKey: .notes)
        try container.encode(linkMethodRaw, forKey: .linkMethodRaw)
        try container.encode(linkStateRaw, forKey: .linkStateRaw)
        try container.encode(max(30, telemetryIntervalSeconds), forKey: .telemetryIntervalSeconds)
    }
}
