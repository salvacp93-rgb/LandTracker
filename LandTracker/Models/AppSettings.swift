import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .spanish:
            return "Castellano"
        }
    }

    func localized(_ english: String, _ spanish: String) -> String {
        self == .spanish ? spanish : english
    }
}

enum AppMeasurementSystem: String, CaseIterable, Identifiable {
    case imperial
    case metric

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .imperial:
            return language.localized("Imperial", "Imperial")
        case .metric:
            return language.localized("Metric", "Sistema internacional")
        }
    }
}

enum AppCurrency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case mxn = "MXN"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usd:
            return "USD ($)"
        case .eur:
            return "EUR (€)"
        case .gbp:
            return "GBP (£)"
        case .mxn:
            return "MXN ($)"
        }
    }
}

enum AppSettings {
    static let defaultLanguage: AppLanguage = .english
    static let defaultMeasurementSystem: AppMeasurementSystem = .imperial
    static let defaultCurrency: AppCurrency = .usd

    private static let hectaresPerAcre = 0.40468564224

    static func language(from raw: String) -> AppLanguage {
        AppLanguage(rawValue: raw) ?? defaultLanguage
    }

    static func measurementSystem(from raw: String) -> AppMeasurementSystem {
        AppMeasurementSystem(rawValue: raw) ?? defaultMeasurementSystem
    }

    static func currencyCode(from raw: String) -> String {
        AppCurrency(rawValue: raw)?.rawValue ?? defaultCurrency.rawValue
    }

    static func areaValue(fromAcres acres: Double, system: AppMeasurementSystem) -> Double {
        switch system {
        case .imperial:
            return acres
        case .metric:
            return acres * hectaresPerAcre
        }
    }

    static func acres(fromAreaValue value: Double, system: AppMeasurementSystem) -> Double {
        switch system {
        case .imperial:
            return value
        case .metric:
            return value / hectaresPerAcre
        }
    }

    static func areaShortUnit(system: AppMeasurementSystem) -> String {
        switch system {
        case .imperial:
            return "ac"
        case .metric:
            return "ha"
        }
    }

    static func areaLongUnit(system: AppMeasurementSystem, language: AppLanguage) -> String {
        switch system {
        case .imperial:
            return language.localized("acres", "acres")
        case .metric:
            return language.localized("hectares", "hectáreas")
        }
    }

    static func formatArea(acres: Double, system: AppMeasurementSystem, language: AppLanguage, fractionDigits: Int = 2) -> String {
        let value = areaValue(fromAcres: acres, system: system)
        let unit = areaLongUnit(system: system, language: language)
        let formatted = value.formatted(.number.precision(.fractionLength(fractionDigits)))
        return "\(formatted) \(unit)"
    }
}
