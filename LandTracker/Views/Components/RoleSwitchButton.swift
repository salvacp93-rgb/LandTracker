import SwiftUI

struct RoleSwitchButton: View {
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var backgroundTint: Color {
        roleAccessViewModel.activeRole == .owner ? .blue : .teal
    }

    var body: some View {
        Menu {
            ForEach(roleAccessViewModel.availableRoles) { role in
                Button {
                    roleAccessViewModel.selectRole(role)
                } label: {
                    if role == roleAccessViewModel.activeRole {
                        Label(role.displayName(language: language), systemImage: "checkmark.circle.fill")
                    } else {
                        Label(role.displayName(language: language), systemImage: role.symbolName)
                    }
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(backgroundTint.opacity(0.95))
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)

                Image(systemName: roleAccessViewModel.activeRole.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            )
        }
        .disabled(!roleAccessViewModel.canSwitchAccessRole)
        .accessibilityLabel(
            language.localized(
                "Change role. Current role: \(roleAccessViewModel.activeRole.displayName(language: language))",
                "Cambiar rol. Rol actual: \(roleAccessViewModel.activeRole.displayName(language: language))"
            )
        )
    }
}
