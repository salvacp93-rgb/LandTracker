import Foundation
import Combine

@MainActor
final class RoleAccessViewModel: ObservableObject {
    @Published private(set) var availableRoles: [AppAccessRole]
    @Published private(set) var activeRole: AppAccessRole
    @Published private(set) var isRefreshing = false
    @Published private(set) var organizationRoles: Set<String> = []

    private let defaults = UserDefaults.standard

    init() {
        let storedRole = defaults.string(forKey: AccountPreferences.activeAccessRoleKey).flatMap(AppAccessRole.init(rawValue:))
        let initialRole = storedRole ?? .employee
        self.activeRole = initialRole
        self.availableRoles = [initialRole]
    }

    var canViewEconomics: Bool {
        activeRole.canViewEconomics
    }

    var canManageStructure: Bool {
        activeRole.canManageStructure
    }

    var canManageExpenses: Bool {
        activeRole.canManageExpenses
    }

    var canUseDailyOperations: Bool {
        activeRole.canUseDailyOperations
    }

    var hasOwnerAccess: Bool {
        availableRoles.contains(.owner) || organizationRoles.contains("owner")
    }

    var hasAdminAccess: Bool {
        hasOwnerAccess || organizationRoles.contains("admin")
    }

    var canManageTeam: Bool {
        hasAdminAccess
    }

    var canSwitchAccessRole: Bool {
        false
    }

    func refreshRolesFromCloud() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let remoteRoles = try await SupabaseSyncService.shared.fetchCurrentUserOrganizationRoles()
            let mapped = AppAccessRole.appRoles(from: remoteRoles)
            organizationRoles = Set(remoteRoles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            applyAvailableRoles(mapped)
        } catch {
            if availableRoles.isEmpty {
                organizationRoles = ["owner"]
                applyAvailableRoles([.owner])
            }
        }
    }

    func selectRole(_ role: AppAccessRole) {
        guard availableRoles.contains(role) else { return }
        activeRole = role
        defaults.set(role.rawValue, forKey: AccountPreferences.activeAccessRoleKey)
    }

    func resetForSignedOut() {
        organizationRoles = []
        availableRoles = [.employee]
        activeRole = .employee
        defaults.removeObject(forKey: AccountPreferences.activeAccessRoleKey)
    }

    private func applyAvailableRoles(_ roles: [AppAccessRole]) {
        let resolved = roles.isEmpty ? [AppAccessRole.owner] : roles
        availableRoles = resolved

        if !resolved.contains(activeRole) {
            if resolved.contains(.owner) {
                activeRole = .owner
            } else {
                activeRole = resolved[0]
            }
            defaults.set(activeRole.rawValue, forKey: AccountPreferences.activeAccessRoleKey)
        }
    }
}
