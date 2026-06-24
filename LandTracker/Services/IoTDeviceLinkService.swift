import Foundation

final class IoTDeviceLinkService {
    static let shared = IoTDeviceLinkService()

    private init() {}

    func normalizedIntervalSeconds(
        requestedMinutes: Int,
        method: LandDeviceLinkMethod
    ) -> Int {
        let requestedSeconds = max(60, requestedMinutes * 60)
        switch method {
        case .bluetooth:
            return max(30, min(15 * 60, requestedSeconds))
        case .cloudAPI, .mqttGateway:
            return max(60, min(60 * 60, requestedSeconds))
        case .manual:
            return max(5 * 60, min(24 * 60 * 60, requestedSeconds))
        }
    }

    func recommendedMethod(for type: LandDeviceType) -> LandDeviceLinkMethod {
        switch type {
        case .waterPump, .inverter, .energyMeter:
            return .cloudAPI
        case .thermometer, .humiditySensor, .rainGauge, .pressureSensor:
            return .bluetooth
        case .other:
            return .manual
        }
    }
}
