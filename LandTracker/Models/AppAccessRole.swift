import Foundation

enum AppAccessRole: String, CaseIterable, Identifiable {
    case owner
    case employee

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .owner:
            return "person.crop.circle.badge.checkmark"
        case .employee:
            return "person.crop.circle.badge.clock"
        }
    }

    var canViewEconomics: Bool {
        self == .owner
    }

    var canManageStructure: Bool {
        self == .owner
    }

    var canManageExpenses: Bool {
        true
    }

    var canUseDailyOperations: Bool {
        true
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .owner:
            return language.localized("Owner", "Propietario")
        case .employee:
            return language.localized("Employee", "Empleado")
        }
    }

    static func appRoles(from organizationRoles: [String]) -> [AppAccessRole] {
        var roles = Set<AppAccessRole>()

        for role in organizationRoles {
            switch role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "owner":
                roles.insert(.owner)
            case "admin", "member", "viewer":
                roles.insert(.employee)
            default:
                continue
            }
        }

        if roles.isEmpty {
            return [.owner]
        }

        return AppAccessRole.allCases.filter { roles.contains($0) }
    }
}
