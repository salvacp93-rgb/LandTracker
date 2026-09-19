import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel

    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @AppStorage(AccountPreferences.measurementSystemKey) private var measurementSystemRaw = AppSettings.defaultMeasurementSystem.rawValue
    @AppStorage(AccountPreferences.preferredCurrencyCodeKey) private var preferredCurrencyCode = AppSettings.defaultCurrency.rawValue

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                languageCard
                unitsCard
                if roleAccessViewModel.canViewEconomics {
                    currencyCard
                }
            }
            .font(.poppins(.body))
            .padding(16)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppBackground())
        .navigationTitle(language.localized("Settings", "Configuración"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(language.localized("Close", "Cerrar")) {
                    dismiss()
                }
            }
        }
    }

    private var languageCard: some View {
        GlassPanelCard(
            title: language.localized("Language", "Idioma"),
            subtitle: language.localized("Pick the language used across the interface.", "Elige el idioma que se usa en toda la interfaz."),
            systemImage: "globe",
            tint: AppTheme.olive
        ) {
            settingsFieldShell(
                label: language.localized("App language", "Idioma de la app"),
                systemImage: "textformat",
                tint: AppTheme.olive
            ) {
                Picker(
                    language.localized("App language", "Idioma de la app"),
                    selection: $appLanguageRaw
                ) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(item.displayName).tag(item.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var unitsCard: some View {
        GlassPanelCard(
            title: language.localized("Units", "Unidades"),
            subtitle: language.localized("Choose how area and related values are displayed.", "Elige como se muestran la superficie y los valores relacionados."),
            systemImage: "ruler.fill",
            tint: AppTheme.clay
        ) {
            settingsFieldShell(
                label: language.localized("Measurement system", "Sistema de medidas"),
                systemImage: "scalemass.fill",
                tint: AppTheme.clay
            ) {
                Picker(
                    language.localized("Measurement system", "Sistema de medidas"),
                    selection: $measurementSystemRaw
                ) {
                    ForEach(AppMeasurementSystem.allCases) { item in
                        Text(item.displayName(language: language)).tag(item.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var currencyCard: some View {
        GlassPanelCard(
            title: language.localized("Currency", "Moneda"),
            subtitle: language.localized("Financial figures keep this display currency across lists and detail views.", "Las cifras economicas mantienen esta moneda en listas y vistas de detalle."),
            systemImage: "banknote.fill",
            tint: AppTheme.highlight
        ) {
            settingsFieldShell(
                label: language.localized("Display currency", "Moneda para cifras"),
                systemImage: "creditcard.fill",
                tint: AppTheme.highlight
            ) {
                Picker(
                    language.localized("Display currency", "Moneda para cifras"),
                    selection: $preferredCurrencyCode
                ) {
                    ForEach(AppCurrency.allCases) { item in
                        Text(item.displayName).tag(item.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func settingsFieldShell<Content: View>(
        label: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(label)
                    .font(.poppins(.caption, .semibold))
            } icon: {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint)

            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.18), lineWidth: 1)
                )
        }
    }
}
