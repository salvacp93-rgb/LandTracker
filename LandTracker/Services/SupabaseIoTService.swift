import Foundation
import Supabase

struct IoTCloudDeviceRecord: Codable, Identifiable {
    let id: UUID
    let organizationID: UUID
    let landID: UUID
    let name: String
    let typeRaw: String
    let manufacturer: String
    let model: String
    let serialNumber: String
    let metricName: String
    let metricUnit: String
    let notes: String
    let isActive: Bool
    let installedAt: Date?
    let lastSeenAt: Date?
    let lastMetricName: String?
    let lastMetricUnit: String?
    let lastReadingValue: Double?
    let lastBatteryLevel: Double?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case organizationID = "organization_id"
        case landID = "land_id"
        case name
        case typeRaw = "type_raw"
        case manufacturer
        case model
        case serialNumber = "serial_number"
        case metricName = "metric_name"
        case metricUnit = "metric_unit"
        case notes
        case isActive = "is_active"
        case installedAt = "installed_at"
        case lastSeenAt = "last_seen_at"
        case lastMetricName = "last_metric_name"
        case lastMetricUnit = "last_metric_unit"
        case lastReadingValue = "last_reading_value"
        case lastBatteryLevel = "last_battery_level"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct IoTTelemetryRecord: Codable, Identifiable {
    let id: Int64
    let organizationID: UUID
    let landID: UUID
    let deviceID: UUID
    let observedAt: Date
    let metricName: String
    let metricUnit: String
    let valueDouble: Double?
    let valueText: String?
    let batteryLevel: Double?
    let statusRaw: String
    let sourceRaw: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case organizationID = "organization_id"
        case landID = "land_id"
        case deviceID = "device_id"
        case observedAt = "observed_at"
        case metricName = "metric_name"
        case metricUnit = "metric_unit"
        case valueDouble = "value_double"
        case valueText = "value_text"
        case batteryLevel = "battery_level"
        case statusRaw = "status_raw"
        case sourceRaw = "source_raw"
        case createdAt = "created_at"
    }
}

struct IoTDeviceCommandRecord: Codable, Identifiable {
    let id: UUID
    let organizationID: UUID
    let landID: UUID
    let deviceID: UUID
    let commandType: String
    let commandState: String
    let requestedAt: Date
    let acknowledgedAt: Date?
    let errorText: String?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case organizationID = "organization_id"
        case landID = "land_id"
        case deviceID = "device_id"
        case commandType = "command_type"
        case commandState = "command_state"
        case requestedAt = "requested_at"
        case acknowledgedAt = "acknowledged_at"
        case errorText = "error_text"
        case updatedAt = "updated_at"
    }
}

final class SupabaseIoTService {
    static let shared = SupabaseIoTService()

    private enum Constants {
        static let devicesTable = "iot_devices"
        static let telemetryTable = "iot_device_telemetry"
        static let commandsTable = "iot_device_commands"
    }

    private let authService = SupabaseAuthService.shared

    private init() {}

    func syncDevices(_ devices: [LandDevice], landID: UUID) async throws {
        for device in devices {
            _ = try await registerDevice(device, landID: landID)
            _ = try? await pushSnapshotTelemetry(for: device)
        }
    }

    @discardableResult
    func registerDevice(_ device: LandDevice, landID: UUID) async throws -> UUID {
        let params = RegisterIoTDeviceParams(
            landID: landID,
            deviceID: device.id,
            name: device.name,
            typeRaw: device.type.rawValue,
            manufacturer: device.manufacturer,
            model: device.model,
            serialNumber: device.serialNumber,
            metricName: device.metricName,
            metricUnit: device.metricUnit,
            installedAt: device.installedAt,
            isActive: device.isActive,
            notes: device.notes,
            metadataText: "{}"
        )

        let deviceID: UUID = try await authService.client
            .rpc("register_iot_device", params: params)
            .execute()
            .value

        return deviceID
    }

    func removeDevice(deviceID: UUID) async throws {
        try await authService.client
            .from(Constants.devicesTable)
            .delete()
            .eq("id", value: deviceID.uuidString)
            .execute()
    }

    func fetchDevices(landID: UUID) async throws -> [IoTCloudDeviceRecord] {
        try await authService.client
            .from(Constants.devicesTable)
            .select()
            .eq("land_id", value: landID.uuidString)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func fetchRecentTelemetry(landID: UUID, limit: Int = 240) async throws -> [IoTTelemetryRecord] {
        try await authService.client
            .from(Constants.telemetryTable)
            .select()
            .eq("land_id", value: landID.uuidString)
            .order("observed_at", ascending: false)
            .limit(max(1, limit))
            .execute()
            .value
    }

    func fetchRecentTelemetry(deviceID: UUID, limit: Int = 120) async throws -> [IoTTelemetryRecord] {
        try await authService.client
            .from(Constants.telemetryTable)
            .select()
            .eq("device_id", value: deviceID.uuidString)
            .order("observed_at", ascending: false)
            .limit(max(1, limit))
            .execute()
            .value
    }

    @discardableResult
    func pushSnapshotTelemetry(for device: LandDevice, source: String = "app_snapshot") async throws -> Int64? {
        guard
            device.lastReadingValue != nil ||
            device.batteryLevel != nil ||
            device.lastSeenAt != nil
        else {
            return nil
        }

        return try await appendTelemetry(
            deviceID: device.id,
            observedAt: device.lastSeenAt ?? Date(),
            metricName: normalized(device.metricName),
            metricUnit: normalized(device.metricUnit),
            valueDouble: device.lastReadingValue,
            valueText: nil,
            batteryLevel: device.batteryLevel,
            statusRaw: device.isActive ? "active" : "inactive",
            sourceRaw: source,
            payload: [:]
        )
    }

    @discardableResult
    func appendTelemetry(
        deviceID: UUID,
        observedAt: Date = Date(),
        metricName: String? = nil,
        metricUnit: String? = nil,
        valueDouble: Double? = nil,
        valueText: String? = nil,
        batteryLevel: Double? = nil,
        statusRaw: String? = nil,
        sourceRaw: String = "manual",
        payload: [String: String] = [:]
    ) async throws -> Int64 {
        let params = AppendIoTTelemetryParams(
            deviceID: deviceID,
            observedAt: observedAt,
            metricName: metricName,
            metricUnit: metricUnit,
            valueDouble: valueDouble,
            valueText: valueText,
            batteryLevel: batteryLevel,
            statusRaw: statusRaw,
            sourceRaw: sourceRaw,
            payloadText: jsonString(from: payload)
        )

        let rowID: Int64 = try await authService.client
            .rpc("append_iot_telemetry", params: params)
            .execute()
            .value

        return rowID
    }

    @discardableResult
    func enqueueCommand(
        deviceID: UUID,
        commandType: String,
        payload: [String: String] = [:]
    ) async throws -> UUID {
        let params = EnqueueIoTCommandParams(
            deviceID: deviceID,
            commandType: commandType,
            commandPayloadText: jsonString(from: payload)
        )

        let commandID: UUID = try await authService.client
            .rpc("enqueue_iot_device_command", params: params)
            .execute()
            .value

        return commandID
    }

    func fetchPendingCommands(deviceID: UUID, limit: Int = 50) async throws -> [IoTDeviceCommandRecord] {
        try await authService.client
            .from(Constants.commandsTable)
            .select()
            .eq("device_id", value: deviceID.uuidString)
            .eq("command_state", value: "pending")
            .order("requested_at", ascending: true)
            .limit(max(1, limit))
            .execute()
            .value
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func jsonString(from dictionary: [String: String]) -> String {
        guard !dictionary.isEmpty else { return "{}" }
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private struct RegisterIoTDeviceParams: nonisolated Encodable, Sendable {
    let landID: UUID
    let deviceID: UUID?
    let name: String
    let typeRaw: String
    let manufacturer: String
    let model: String
    let serialNumber: String
    let metricName: String
    let metricUnit: String
    let installedAt: Date?
    let isActive: Bool
    let notes: String
    let metadataText: String

    enum CodingKeys: String, CodingKey {
        case landID = "p_land_id"
        case deviceID = "p_device_id"
        case name = "p_name"
        case typeRaw = "p_type_raw"
        case manufacturer = "p_manufacturer"
        case model = "p_model"
        case serialNumber = "p_serial_number"
        case metricName = "p_metric_name"
        case metricUnit = "p_metric_unit"
        case installedAt = "p_installed_at"
        case isActive = "p_is_active"
        case notes = "p_notes"
        case metadataText = "p_metadata_text"
    }
}

private struct AppendIoTTelemetryParams: nonisolated Encodable, Sendable {
    let deviceID: UUID
    let observedAt: Date
    let metricName: String?
    let metricUnit: String?
    let valueDouble: Double?
    let valueText: String?
    let batteryLevel: Double?
    let statusRaw: String?
    let sourceRaw: String
    let payloadText: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
        case observedAt = "p_observed_at"
        case metricName = "p_metric_name"
        case metricUnit = "p_metric_unit"
        case valueDouble = "p_value_double"
        case valueText = "p_value_text"
        case batteryLevel = "p_battery_level"
        case statusRaw = "p_status_raw"
        case sourceRaw = "p_source_raw"
        case payloadText = "p_payload_text"
    }
}

private struct EnqueueIoTCommandParams: nonisolated Encodable, Sendable {
    let deviceID: UUID
    let commandType: String
    let commandPayloadText: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
        case commandType = "p_command_type"
        case commandPayloadText = "p_command_payload_text"
    }
}
