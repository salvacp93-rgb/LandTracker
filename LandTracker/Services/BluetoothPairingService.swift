import Foundation
import CoreBluetooth
import Combine

struct BluetoothScanDevice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
    let lastSeenAt: Date
}

struct BluetoothDataSample: Hashable {
    let observedAt: Date
    let serviceUUID: String
    let characteristicUUID: String
    let valueDouble: Double?
    let valueText: String?
    let rawHex: String

    var displayValue: String {
        if let valueDouble {
            return valueDouble.formatted(.number.precision(.fractionLength(2)))
        }
        if let valueText, !valueText.isEmpty {
            return valueText
        }
        return rawHex
    }
}

@MainActor
final class BluetoothPairingService: NSObject, ObservableObject {
    private static let genericDeviceName = "Bluetooth device"

    @Published private(set) var managerState: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var isConnecting = false
    @Published private(set) var discoveredDevices: [BluetoothScanDevice] = []
    @Published private(set) var connectedDeviceID: UUID?
    @Published private(set) var latestSample: BluetoothDataSample?
    @Published private(set) var lastError: String?

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var devicesByID: [UUID: BluetoothScanDevice] = [:]
    private var orderedDeviceIDs: [UUID] = []
    private var subscribedCharacteristicUUIDs: Set<CBUUID> = []
    private var readCharacteristicUUIDs: Set<CBUUID> = []
    private var pendingPublishTask: Task<Void, Never>?

    var isBluetoothReady: Bool {
        managerState == .poweredOn
    }

    var connectedDevice: BluetoothScanDevice? {
        guard let connectedDeviceID else { return nil }
        return devicesByID[connectedDeviceID]
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    func startScanning() {
        guard isBluetoothReady else { return }
        pendingPublishTask?.cancel()
        pendingPublishTask = nil
        lastError = nil
        discoveredDevices = []
        devicesByID = [:]
        peripheralsByID = [:]
        orderedDeviceIDs = []
        connectedDeviceID = nil
        latestSample = nil
        connectedPeripheral = nil
        subscribedCharacteristicUUIDs = []
        readCharacteristicUUIDs = []
        isScanning = true

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScanning() {
        guard isScanning else { return }
        centralManager.stopScan()
        pendingPublishTask?.cancel()
        pendingPublishTask = nil
        publishDiscoveredDevices()
        isScanning = false
    }

    func resetSession() {
        pendingPublishTask?.cancel()
        pendingPublishTask = nil
        if isScanning {
            centralManager.stopScan()
        }
        if let connectedPeripheral {
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        }

        isScanning = false
        isConnecting = false
        discoveredDevices = []
        connectedDeviceID = nil
        latestSample = nil
        lastError = nil
        connectedPeripheral = nil
        peripheralsByID = [:]
        devicesByID = [:]
        orderedDeviceIDs = []
        subscribedCharacteristicUUIDs = []
        readCharacteristicUUIDs = []
    }

    func connect(to deviceID: UUID) {
        guard let peripheral = peripheralsByID[deviceID] else { return }
        lastError = nil
        isConnecting = true
        centralManager.connect(peripheral)
    }

    private func setManagerState(_ state: CBManagerState) {
        managerState = state
        if state != .poweredOn {
            stopScanning()
            isConnecting = false
            connectedDeviceID = nil
            connectedPeripheral = nil
            latestSample = nil
            subscribedCharacteristicUUIDs = []
            readCharacteristicUUIDs = []
        }
    }

    private func updateDiscoveredPeripheral(
        _ peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        let nameFromAdvertisement = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rawName = nameFromAdvertisement ?? peripheral.name ?? Self.genericDeviceName
        let normalizedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = normalizedName.isEmpty ? Self.genericDeviceName : normalizedName
        let now = Date()
        let deviceID = peripheral.identifier

        let device: BluetoothScanDevice
        if let existing = devicesByID[deviceID] {
            device = BluetoothScanDevice(
                id: existing.id,
                name: resolvedDeviceName(current: existing.name, candidate: safeName),
                rssi: smoothedRSSI(current: existing.rssi, next: rssi.intValue),
                lastSeenAt: now
            )
        } else {
            device = BluetoothScanDevice(
                id: deviceID,
                name: safeName,
                rssi: rssi.intValue,
                lastSeenAt: now
            )
            insertDeviceInStableOrder(device)
        }

        peripheralsByID[deviceID] = peripheral
        devicesByID[deviceID] = device
        scheduleDevicesPublish()
    }

    private func handleDidConnect(_ peripheral: CBPeripheral) {
        isConnecting = false
        connectedDeviceID = peripheral.identifier
        connectedPeripheral = peripheral
        latestSample = nil
        subscribedCharacteristicUUIDs = []
        readCharacteristicUUIDs = []
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        stopScanning()
    }

    private func handleDidFailToConnect(_ error: Error?) {
        isConnecting = false
        lastError = error?.localizedDescription ?? "Could not connect to this Bluetooth device."
    }

    private func resolvedDeviceName(current: String, candidate: String) -> String {
        let normalizedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedCurrent == Self.genericDeviceName && normalizedCandidate != Self.genericDeviceName {
            return normalizedCandidate
        }
        return normalizedCurrent.isEmpty ? normalizedCandidate : normalizedCurrent
    }

    private func smoothedRSSI(current: Int, next: Int) -> Int {
        let blended = Int((Double(current) * 0.7) + (Double(next) * 0.3))
        return abs(blended - current) < 2 ? current : blended
    }

    private func insertDeviceInStableOrder(_ device: BluetoothScanDevice) {
        let insertionIndex = orderedDeviceIDs.firstIndex { existingID in
            guard let existing = devicesByID[existingID] else { return false }
            if device.rssi == existing.rssi {
                return device.name.localizedCaseInsensitiveCompare(existing.name) == .orderedAscending
            }
            return device.rssi > existing.rssi
        } ?? orderedDeviceIDs.endIndex

        orderedDeviceIDs.insert(device.id, at: insertionIndex)
    }

    private func scheduleDevicesPublish() {
        guard pendingPublishTask == nil else { return }

        pendingPublishTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            publishDiscoveredDevices()
            pendingPublishTask = nil
        }
    }

    private func publishDiscoveredDevices() {
        discoveredDevices = orderedDeviceIDs.compactMap { devicesByID[$0] }
    }

    private func handleDidDiscoverServices(_ peripheral: CBPeripheral, error: Error?) {
        if let error {
            lastError = error.localizedDescription
            return
        }
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    private func handleDidDiscoverCharacteristics(
        _ peripheral: CBPeripheral,
        service: CBService,
        error: Error?
    ) {
        if let error {
            lastError = error.localizedDescription
            return
        }
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            let properties = characteristic.properties

            if (properties.contains(.notify) || properties.contains(.indicate)) && !subscribedCharacteristicUUIDs.contains(characteristic.uuid) {
                subscribedCharacteristicUUIDs.insert(characteristic.uuid)
                peripheral.setNotifyValue(true, for: characteristic)
            }

            if properties.contains(.read) && !readCharacteristicUUIDs.contains(characteristic.uuid) {
                readCharacteristicUUIDs.insert(characteristic.uuid)
                peripheral.readValue(for: characteristic)
            }
        }
    }

    private func handleDidUpdateValue(
        _ characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            lastError = error.localizedDescription
            return
        }

        guard let data = characteristic.value, !data.isEmpty else { return }
        let serviceUUID = characteristic.service?.uuid.uuidString ?? "unknown_service"
        let characteristicUUID = characteristic.uuid.uuidString
        latestSample = parsedSample(
            from: data,
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID
        )
    }

    private func parsedSample(
        from data: Data,
        serviceUUID: String,
        characteristicUUID: String
    ) -> BluetoothDataSample {
        let hex = data.hexEncodedString()

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return BluetoothDataSample(
                observedAt: Date(),
                serviceUUID: serviceUUID,
                characteristicUUID: characteristicUUID,
                valueDouble: firstNumber(in: text),
                valueText: text,
                rawHex: hex
            )
        }

        let numericValue = numericValueFromRawBytes(data)
        return BluetoothDataSample(
            observedAt: Date(),
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            valueDouble: numericValue,
            valueText: nil,
            rawHex: hex
        )
    }

    private func firstNumber(in text: String) -> Double? {
        guard let range = text.range(of: "-?\\d+(?:[\\.,]\\d+)?", options: .regularExpression) else {
            return nil
        }
        let extracted = String(text[range]).replacingOccurrences(of: ",", with: ".")
        return Double(extracted)
    }

    private func numericValueFromRawBytes(_ data: Data) -> Double? {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }

        switch bytes.count {
        case 1:
            return Double(bytes[0])
        case 2:
            let unsigned = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            return Double(unsigned)
        case 4:
            let raw = UInt32(bytes[0]) |
                (UInt32(bytes[1]) << 8) |
                (UInt32(bytes[2]) << 16) |
                (UInt32(bytes[3]) << 24)
            let floatValue = Float(bitPattern: raw)
            if floatValue.isFinite && abs(floatValue) < 1_000_000_000 {
                return Double(floatValue)
            }
            return Double(raw)
        case 8:
            let raw = UInt64(bytes[0]) |
                (UInt64(bytes[1]) << 8) |
                (UInt64(bytes[2]) << 16) |
                (UInt64(bytes[3]) << 24) |
                (UInt64(bytes[4]) << 32) |
                (UInt64(bytes[5]) << 40) |
                (UInt64(bytes[6]) << 48) |
                (UInt64(bytes[7]) << 56)
            let doubleValue = Double(bitPattern: raw)
            if doubleValue.isFinite && abs(doubleValue) < 1_000_000_000 {
                return doubleValue
            }
            return Double(raw)
        default:
            return nil
        }
    }
}

extension BluetoothPairingService: nonisolated CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            setManagerState(central.state)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            updateDiscoveredPeripheral(peripheral, advertisementData: advertisementData, rssi: RSSI)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            handleDidConnect(peripheral)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            handleDidFailToConnect(error)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            if connectedDeviceID == peripheral.identifier {
                connectedDeviceID = nil
                connectedPeripheral = nil
                latestSample = nil
                subscribedCharacteristicUUIDs = []
                readCharacteristicUUIDs = []
            }
            if let error {
                lastError = error.localizedDescription
            }
        }
    }
}

extension BluetoothPairingService: nonisolated CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            handleDidDiscoverServices(peripheral, error: error)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            handleDidDiscoverCharacteristics(peripheral, service: service, error: error)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            handleDidUpdateValue(characteristic, error: error)
        }
    }
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02X", $0) }.joined()
    }
}
