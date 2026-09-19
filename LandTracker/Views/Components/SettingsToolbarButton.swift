import SwiftUI

struct SettingsToolbarButton: View {
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("IconGear")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .frame(width: 30, height: 30)
                .background(AppTheme.card, in: Circle())
                .overlay(Circle().strokeBorder(AppTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.localized("Settings", "Configuración"))
    }
}
