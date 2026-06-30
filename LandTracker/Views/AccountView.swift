import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel
    @ObservedObject private var profileImageStore = ProfileImageStore.shared
    @Query private var lands: [Land]
    @Query private var groups: [LandGroup]
    @Query(sort: \PendingSyncOperation.createdAt) private var pendingOperations: [PendingSyncOperation]

    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @AppStorage(AccountPreferences.displayNameKey) private var displayName = ""
    @AppStorage(AccountPreferences.accountTypeKey) private var accountTypeRaw = "individual"
    @AppStorage(AccountPreferences.profilePhotoPathKey) private var profilePhotoPath = ""
    @AppStorage(AccountPreferences.cachedEmailKey) private var cachedEmail = ""
    @AppStorage(AccountPreferences.showIncomeInListKey) private var showIncomeInList = true
    @AppStorage(AccountPreferences.showSubtypeInListKey) private var showSubtypeInList = true
    @AppStorage(AccountPreferences.spreadsheetSourceFileNameKey) private var spreadsheetSourceFileName = ""
    @AppStorage(AccountPreferences.spreadsheetSourcePathKey) private var spreadsheetSourcePath = ""
    @AppStorage(AccountPreferences.spreadsheetSourceHashKey) private var spreadsheetSourceHash = ""
    @AppStorage(AccountPreferences.spreadsheetSourceUpdatedAtKey) private var spreadsheetSourceUpdatedAt = 0.0
    @AppStorage(AccountPreferences.spreadsheetLastProcessedHashKey) private var spreadsheetLastProcessedHash = ""
    @AppStorage(AccountPreferences.spreadsheetLastProcessedAtKey) private var spreadsheetLastProcessedAt = 0.0

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isSavingPhoto = false
    @State private var isSavingProfile = false
    @State private var isSyncingNow = false
    @State private var isProcessingSpreadsheet = false
    @State private var statusMessage: String?
    @State private var photoError: String?
    @State private var spreadsheetError: String?
    @State private var showingSpreadsheetImporter = false

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                accountHeroCard
                accountSection
                basicPreferencesSection
                syncSection
                if roleAccessViewModel.hasOwnerAccess {
                    spreadsheetSection
                }
                signOutSection
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(language.localized("Account", "Cuenta"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(language.localized("Close", "Cerrar")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await saveAccountProfile()
                    }
                } label: {
                    if isSavingProfile {
                        ProgressView()
                    } else {
                        Text(language.localized("Save", "Guardar"))
                    }
                }
                .disabled(isInteractionBlocked)
            }
        }
        .onAppear {
            Task {
                await refreshProfileFromCloud()
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                await saveSelectedPhoto(newValue)
            }
        }
        .fileImporter(
            isPresented: $showingSpreadsheetImporter,
            allowedContentTypes: spreadsheetAllowedContentTypes
        ) { result in
            Task {
                await handleSpreadsheetImportResult(result)
            }
        }
        .alert(language.localized("Account", "Cuenta"), isPresented: isShowingStatusAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
    }

    private var isInteractionBlocked: Bool {
        isSavingPhoto || isSavingProfile || isSyncingNow || isProcessingSpreadsheet
    }

    private var hasCloudSpreadsheetReference: Bool {
        !spreadsheetSourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var retryPendingDisabled: Bool {
        isInteractionBlocked || pendingOperations.isEmpty
    }

    private var pendingLastError: String? {
        pendingOperations.compactMap(\.lastError).last
    }

    private var isShowingStatusAlert: Binding<Bool> {
        Binding(
            get: { statusMessage != nil },
            set: { shouldShow in
                if !shouldShow {
                    statusMessage = nil
                }
            }
        )
    }

    private var accountHeroGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: 10),
            GridItem(.flexible(minimum: 0), spacing: 10)
        ]
    }

    private var accountHeroTitle: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if !accountEmail.isEmpty && accountEmail != localizedUnavailableText {
            return accountEmail
        }
        return language.localized("My account", "Mi cuenta")
    }

    private var accountHeroSubtitle: String {
        accountEmail
    }

    private var accountHeroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.46, blue: 0.87),
                            Color(red: 0.16, green: 0.67, blue: 0.51)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ProfileAvatarView(imageData: profileImageData, size: 76)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.34), lineWidth: 1.2)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(accountHeroTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)

                        Text(accountHeroSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.88))

                        HStack(spacing: 8) {
                            heroBadge(
                                title: language.localized("Type", "Tipo"),
                                value: accountTypeDisplayName,
                                systemImage: accountTypeSymbol
                            )

                            heroBadge(
                                title: language.localized("Access", "Acceso"),
                                value: roleAccessViewModel.activeRole.displayName(language: language),
                                systemImage: roleAccessViewModel.activeRole.symbolName
                            )
                        }
                    }

                    Spacer(minLength: 0)

                    if isInteractionBlocked {
                        ProgressView()
                            .tint(.white)
                    }
                }

                LazyVGrid(columns: accountHeroGridColumns, spacing: 10) {
                    GlassHeroSummaryTile(
                        title: language.localized("Lands", "Terrenos"),
                        value: "\(lands.count)",
                        systemImage: "square.split.2x1.fill",
                        colors: [Color(red: 0.16, green: 0.55, blue: 0.93), Color(red: 0.11, green: 0.45, blue: 0.84)]
                    )

                    GlassHeroSummaryTile(
                        title: language.localized("Groups", "Grupos"),
                        value: "\(groups.count)",
                        systemImage: "square.grid.2x2.fill",
                        colors: [Color(red: 0.33, green: 0.62, blue: 0.39), Color(red: 0.20, green: 0.55, blue: 0.31)]
                    )

                    GlassHeroSummaryTile(
                        title: language.localized("Pending", "Pendientes"),
                        value: "\(pendingOperations.count)",
                        systemImage: "arrow.triangle.2.circlepath",
                        colors: [Color(red: 0.96, green: 0.66, blue: 0.18), Color(red: 0.91, green: 0.45, blue: 0.20)]
                    )

                    GlassHeroSummaryTile(
                        title: language.localized("Spreadsheet", "Hoja de calculo"),
                        value: roleAccessViewModel.hasOwnerAccess
                            ? language.localized("Enabled", "Activa")
                            : language.localized("Standard", "Estandar"),
                        systemImage: "doc.text.fill",
                        colors: [Color(red: 0.41, green: 0.49, blue: 0.93), Color(red: 0.24, green: 0.35, blue: 0.82)]
                    )
                }
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    private var syncSection: some View {
        GlassPanelCard(
            title: language.localized("Sync", "Sincronizacion"),
            subtitle: language.localized("Control the local queue and force a refresh whenever you need it.", "Controla la cola local y fuerza una actualizacion cuando lo necesites."),
            systemImage: "arrow.triangle.2.circlepath.circle.fill",
            tint: Color(red: 0.18, green: 0.54, blue: 0.92)
        ) {
            accountValueShell(
                label: language.localized("Pending changes", "Cambios pendientes"),
                value: "\(pendingOperations.count)",
                systemImage: "clock.badge.exclamationmark.fill",
                tint: Color(red: 0.96, green: 0.66, blue: 0.18)
            )

            accountValueShell(
                label: language.localized("Last successful sync", "Ultima sincronizacion correcta"),
                value: lastSuccessfulSyncText,
                systemImage: "checkmark.icloud.fill",
                tint: Color(red: 0.19, green: 0.63, blue: 0.40)
            )

            if let lastError = pendingLastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.red.opacity(0.16), lineWidth: 1)
                    )
            }

            VStack(spacing: 10) {
                Button {
                    Task {
                        await syncNow()
                    }
                } label: {
                    if isSyncingNow {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(language.localized("Sync now", "Sincronizar ahora"), systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.18, green: 0.54, blue: 0.92))
                .disabled(isInteractionBlocked)

                Button {
                    Task {
                        await retryPendingNow()
                    }
                } label: {
                    Label(language.localized("Retry pending", "Reintentar pendientes"), systemImage: "clock.arrow.trianglehead.2.counterclockwise.rotate.90")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.18, green: 0.54, blue: 0.92))
                .disabled(retryPendingDisabled)
            }
        }
    }

    private var spreadsheetSection: some View {
        GlassPanelCard(
            title: language.localized("Bulk Data", "Datos masivos"),
            subtitle: language.localized("Keep the CSV source connected so this device can process the latest spreadsheet whenever needed.", "Mantiene conectada la fuente CSV para que este dispositivo pueda procesar la ultima hoja cuando haga falta."),
            systemImage: "tablecells.badge.ellipsis",
            tint: Color(red: 0.58, green: 0.46, blue: 0.92)
        ) {
            if spreadsheetSourceFileName.isEmpty {
                Text(language.localized("No file configured yet.", "No hay archivo configurado todavia."))
                    .foregroundStyle(.secondary)
            } else {
                accountValueShell(
                    label: language.localized("File", "Archivo"),
                    value: spreadsheetSourceFileName,
                    systemImage: "doc.text.fill",
                    tint: Color(red: 0.58, green: 0.46, blue: 0.92)
                )

                accountValueShell(
                    label: language.localized("Latest cloud reference", "Ultima referencia cloud"),
                    value: spreadsheetSourceUpdatedText,
                    systemImage: "icloud.fill",
                    tint: Color(red: 0.23, green: 0.64, blue: 0.91)
                )

                accountValueShell(
                    label: language.localized("Cloud hash", "Hash cloud"),
                    value: shortHash(spreadsheetSourceHash),
                    systemImage: "number.square.fill",
                    tint: Color(red: 0.23, green: 0.64, blue: 0.91),
                    isMonospaced: true
                )
            }

            accountValueShell(
                label: language.localized("Latest local processing", "Ultimo proceso local"),
                value: lastProcessedSpreadsheetText,
                systemImage: "desktopcomputer",
                tint: Color(red: 0.96, green: 0.66, blue: 0.18)
            )

            if let spreadsheetError {
                Text(spreadsheetError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                showingSpreadsheetImporter = true
            } label: {
                if isProcessingSpreadsheet {
                    ProgressView()
                } else {
                    Label(language.localized("Upload and process CSV", "Subir y procesar CSV"), systemImage: "doc.badge.plus")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.58, green: 0.46, blue: 0.92))
            .disabled(isInteractionBlocked)

            Button {
                Task {
                    await processSpreadsheetFromCloudReference()
                }
            } label: {
                Label(language.localized("Process cloud file on this device", "Procesar archivo cloud en este dispositivo"), systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .tint(Color(red: 0.58, green: 0.46, blue: 0.92))
            .disabled(isInteractionBlocked || !hasCloudSpreadsheetReference)

            Text(
                language.localized(
                    "Expected format: CSV exported from Excel. Minimum columns: refcat (or land name), year and month.",
                    "Formato esperado: CSV exportado desde Excel. Columnas minimas: refcat (o nombre de terreno), year y month."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var signOutSection: some View {
        GlassPanelCard(systemImage: "door.left.hand.open", tint: Color.red) {
            HStack {
                Spacer(minLength: 0)

                Button(language.localized("Sign out", "Cerrar sesion"), role: .destructive) {
                    Task {
                        await authViewModel.signOut()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)

                Spacer(minLength: 0)
            }
        }
    }

    private var accountSection: some View {
        GlassPanelCard(
            title: language.localized("Profile", "Perfil"),
            subtitle: language.localized("Adjust your visible identity and the details that describe this account.", "Ajusta tu identidad visible y los datos que describen esta cuenta."),
            systemImage: "person.crop.circle.fill",
            tint: Color(red: 0.19, green: 0.63, blue: 0.40)
        ) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(
                        profileImageData == nil
                            ? language.localized("Choose profile photo", "Elegir foto de perfil")
                            : language.localized("Change profile photo", "Cambiar foto de perfil"),
                        systemImage: "photo"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color(red: 0.19, green: 0.63, blue: 0.40))
                .disabled(isInteractionBlocked)

                if profileImageData != nil {
                    Button(language.localized("Remove photo", "Eliminar foto"), role: .destructive) {
                        Task {
                            await removeProfilePhoto()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isInteractionBlocked)
                }
            }

            if isSavingPhoto {
                ProgressView(language.localized("Uploading photo...", "Subiendo foto..."))
                    .font(.footnote)
            }

            if let photoError {
                Text(photoError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            accountFieldShell(
                label: language.localized("Display name", "Nombre visible"),
                systemImage: "character.textbox",
                tint: Color(red: 0.18, green: 0.54, blue: 0.92)
            ) {
                TextField(language.localized("How others will identify you", "Como te identificaran los demas"), text: $displayName)
                    .textInputAutocapitalization(.words)
            }

            accountValueShell(
                label: language.localized("Email", "Email"),
                value: accountEmail,
                systemImage: "envelope.fill",
                tint: Color(red: 0.18, green: 0.54, blue: 0.92)
            )

            accountValueShell(
                label: language.localized("Account type", "Tipo de cuenta"),
                value: accountTypeDisplayName,
                systemImage: accountTypeSymbol,
                tint: Color(red: 0.19, green: 0.63, blue: 0.40)
            )

            accountValueShell(
                label: language.localized("Access role", "Rol de acceso"),
                value: roleAccessViewModel.activeRole.displayName(language: language),
                systemImage: roleAccessViewModel.activeRole.symbolName,
                tint: Color(red: 0.96, green: 0.66, blue: 0.18)
            )
        }
    }

    private var basicPreferencesSection: some View {
        GlassPanelCard(
            title: language.localized("Preferences", "Preferencias"),
            subtitle: language.localized("Choose the level of detail that appears throughout your daily lists.", "Elige el nivel de detalle que aparece en tus listas del dia a dia."),
            systemImage: "slider.horizontal.3",
            tint: Color(red: 0.96, green: 0.66, blue: 0.18)
        ) {
            if roleAccessViewModel.canViewEconomics {
                accountToggleShell(
                    title: language.localized("Show income in lists", "Mostrar ingresos en lista"),
                    subtitle: language.localized("Keep financial context visible at a glance.", "Mantiene el contexto economico visible de un vistazo."),
                    systemImage: "dollarsign.circle.fill",
                    tint: Color(red: 0.18, green: 0.54, blue: 0.92),
                    isOn: $showIncomeInList
                )
            }

            accountToggleShell(
                title: language.localized("Show subtype in lists", "Mostrar subtipo en lista"),
                subtitle: language.localized("Display the crop variety next to each land when available.", "Muestra la variedad del cultivo junto a cada terreno cuando exista."),
                systemImage: "leaf.circle.fill",
                tint: Color(red: 0.19, green: 0.63, blue: 0.40),
                isOn: $showSubtypeInList
            )
        }
    }

    private func heroBadge(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func accountFieldShell<Content: View>(
        label: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.semibold))
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

    private func accountValueShell(
        label: String,
        value: String,
        systemImage: String,
        tint: Color,
        isMonospaced: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(isMonospaced ? .footnote.monospaced() : .body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }

    private func accountToggleShell(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }

    private var profileImageData: Data? {
        profileImageStore.imageData
    }

    private var localizedUnavailableText: String {
        language.localized("Not available", "No disponible")
    }

    private var accountEmail: String {
        if !authViewModel.accountEmail.isEmpty {
            return authViewModel.accountEmail
        }
        if !authViewModel.email.isEmpty {
            return authViewModel.email
        }
        if !cachedEmail.isEmpty {
            return cachedEmail
        }
        return localizedUnavailableText
    }

    private var accountTypeSymbol: String {
        switch accountTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "organization":
            return "building.2.crop.circle.fill"
        default:
            return "person.crop.circle.fill"
        }
    }

    private var accountTypeDisplayName: String {
        switch accountTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "organization":
            return language.localized("Organization / Company", "Organizacion / Empresa")
        default:
            return language.localized("Individual", "Particular")
        }
    }

    private var lastSuccessfulSyncText: String {
        guard let date = SupabaseSyncService.shared.lastSuccessfulSyncAt() else {
            return language.localized("Never", "Nunca")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var spreadsheetAllowedContentTypes: [UTType] {
        [.commaSeparatedText, .plainText]
    }

    private var spreadsheetSourceUpdatedText: String {
        guard spreadsheetSourceUpdatedAt > 0 else { return language.localized("Never", "Nunca") }
        return Date(timeIntervalSince1970: spreadsheetSourceUpdatedAt)
            .formatted(date: .abbreviated, time: .shortened)
    }

    private var lastProcessedSpreadsheetText: String {
        guard spreadsheetLastProcessedAt > 0 else { return language.localized("Never", "Nunca") }
        let dateText = Date(timeIntervalSince1970: spreadsheetLastProcessedAt)
            .formatted(date: .abbreviated, time: .shortened)
        let hashText = spreadsheetLastProcessedHash.isEmpty ? "" : " (\(shortHash(spreadsheetLastProcessedHash)))"
        return "\(dateText)\(hashText)"
    }

    private func shortHash(_ hash: String) -> String {
        let trimmed = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        return String(trimmed.prefix(12))
    }

    private func refreshProfileFromCloud() async {
        do {
            try await SupabaseSyncService.shared.refreshProfileCacheFromCloud(fallbackEmail: accountEmail)
            try? await SupabaseSyncService.shared.refreshSpreadsheetSourceCache()
            photoError = nil
        } catch {
            photoError = language.localized("We could not load your profile from the cloud.", "No se pudo cargar tu perfil desde la nube.")
        }
    }

    private func saveAccountProfile() async {
        isSavingProfile = true
        defer { isSavingProfile = false }

        do {
            try await SupabaseSyncService.shared.upsertProfile(
                displayName: displayName,
                showIncomeInList: showIncomeInList,
                showSubtypeInList: showSubtypeInList,
                profilePhotoPath: profilePhotoPath
            )
            photoError = nil
            statusMessage = language.localized("Profile saved to the cloud.", "Perfil guardado en la nube.")
        } catch {
            photoError = language.localized("We could not save your profile to the cloud.", "No se pudo guardar el perfil en la nube.")
        }
    }

    private func syncNow() async {
        isSyncingNow = true
        defer { isSyncingNow = false }

        do {
            try await SupabaseSyncService.shared.upsertProfile(
                displayName: displayName,
                showIncomeInList: showIncomeInList,
                showSubtypeInList: showSubtypeInList,
                profilePhotoPath: profilePhotoPath
            )
            try await SupabaseSyncService.shared.performStartupSync(context: context)
            photoError = nil
            if pendingOperations.isEmpty {
                statusMessage = language.localized("Sync completed.", "Sincronizacion completada.")
            } else {
                statusMessage = language.localized(
                    "Partial sync completed. \(pendingOperations.count) changes are still pending.",
                    "Sincronizacion parcial. Quedan \(pendingOperations.count) cambios pendientes."
                )
            }
        } catch {
            photoError = language.localized("The sync could not be completed.", "No se pudo completar la sincronizacion.")
        }
    }

    private func retryPendingNow() async {
        isSyncingNow = true
        defer { isSyncingNow = false }

        await SupabaseSyncService.shared.retryPendingOperationsNow(context: context)
        statusMessage = pendingOperations.isEmpty
            ? language.localized("There are no pending changes.", "No hay cambios pendientes.")
            : language.localized("Retry launched. Reviewing the local queue.", "Reintento ejecutado. Revisando cola local.")
    }

    private func removeProfilePhoto() async {
        isSavingPhoto = true
        defer { isSavingPhoto = false }

        do {
            try await SupabaseSyncService.shared.removeProfileImage()
            profilePhotoPath = ""
            try await SupabaseSyncService.shared.upsertProfile(
                displayName: displayName,
                showIncomeInList: showIncomeInList,
                showSubtypeInList: showSubtypeInList,
                profilePhotoPath: nil
            )
            photoError = nil
            statusMessage = language.localized("Profile photo removed.", "Foto de perfil eliminada.")
        } catch {
            photoError = language.localized("We could not remove the photo from the cloud.", "No se pudo eliminar la foto en la nube.")
        }
    }

    private func saveSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        isSavingPhoto = true
        defer {
            isSavingPhoto = false
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = language.localized("The selected photo could not be read.", "No se pudo leer la foto seleccionada.")
                return
            }

            guard let optimizedData = optimizedImageData(from: data) else {
                photoError = language.localized("The photo could not be processed.", "No se pudo procesar la foto.")
                return
            }

            let uploadedPath = try await SupabaseSyncService.shared.uploadProfileImage(optimizedData)
            profilePhotoPath = uploadedPath

            try await SupabaseSyncService.shared.upsertProfile(
                displayName: displayName,
                showIncomeInList: showIncomeInList,
                showSubtypeInList: showSubtypeInList,
                profilePhotoPath: uploadedPath
            )

            photoError = nil
            statusMessage = language.localized("Profile photo saved.", "Foto de perfil guardada.")
        } catch {
            photoError = language.localized("We could not save the photo to the cloud.", "No se pudo guardar la foto en la nube.")
        }
    }

    @MainActor
    private func handleSpreadsheetImportResult(_ result: Result<URL, Error>) async {
        switch result {
        case .failure:
            spreadsheetError = language.localized("The selected file could not be read.", "No se pudo leer el archivo seleccionado.")
        case .success(let url):
            await processSelectedSpreadsheetFile(url)
        }
    }

    @MainActor
    private func processSelectedSpreadsheetFile(_ url: URL) async {
        let ext = url.pathExtension.lowercased()
        guard ext == "csv" || ext == "txt" else {
            spreadsheetError = language.localized("Unsupported format. Export from Excel as CSV and try again.", "Formato no soportado. Exporta desde Excel a CSV e intentalo de nuevo.")
            return
        }

        isProcessingSpreadsheet = true
        defer { isProcessingSpreadsheet = false }

        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try await processSpreadsheetData(
                data,
                fileName: url.lastPathComponent,
                shouldUploadReference: true
            )
        } catch {
            spreadsheetError = error.localizedDescription
        }
    }

    @MainActor
    private func processSpreadsheetFromCloudReference() async {
        try? await SupabaseSyncService.shared.refreshSpreadsheetSourceCache()

        guard let source = SupabaseSyncService.shared.spreadsheetSourceFromCache() else {
            spreadsheetError = language.localized("There is no cloud reference saved for this file.", "No hay referencia cloud guardada para el archivo.")
            return
        }

        if source.fileHash == spreadsheetLastProcessedHash {
            statusMessage = language.localized("This file has already been processed on this device.", "Este archivo ya esta procesado en este dispositivo.")
            return
        }

        isProcessingSpreadsheet = true
        defer { isProcessingSpreadsheet = false }

        do {
            let data = try await SupabaseSyncService.shared.downloadSpreadsheetFile(path: source.storagePath)
            try await processSpreadsheetData(
                data,
                fileName: source.fileName,
                shouldUploadReference: false,
                expectedHash: source.fileHash
            )
        } catch {
            spreadsheetError = error.localizedDescription
        }
    }

    @MainActor
    private func processSpreadsheetData(
        _ data: Data,
        fileName: String,
        shouldUploadReference: Bool,
        expectedHash: String? = nil
    ) async throws {
        let computedHash = SpreadsheetImportService.sha256Hex(for: data)
        let summary = try SpreadsheetImportService.shared.importCSVData(data, context: context)

        spreadsheetLastProcessedHash = computedHash
        spreadsheetLastProcessedAt = Date().timeIntervalSince1970
        spreadsheetError = nil

        if let expectedHash, !expectedHash.isEmpty, expectedHash != computedHash {
            spreadsheetError = language.localized(
                "The cloud file hash does not match the expected one. It was still processed locally.",
                "El hash del archivo cloud no coincide con el esperado. Se proceso igualmente en local."
            )
        }

        if shouldUploadReference {
            do {
                let storagePath = try await SupabaseSyncService.shared.uploadSpreadsheetFile(data, fileName: fileName)
                try await SupabaseSyncService.shared.upsertSpreadsheetSource(
                    fileName: fileName,
                    storagePath: storagePath,
                    fileHash: computedHash
                )
                spreadsheetSourceUpdatedAt = Date().timeIntervalSince1970
            } catch {
                spreadsheetError = language.localized(
                    "The CSV was processed locally, but the cloud reference could not be saved.",
                    "CSV procesado en local, pero no se pudo guardar la referencia en cloud."
                )
            }
        }

        statusMessage =
            language.localized(
                "Process completed: \(summary.linkedRows) linked rows, \(summary.unmatchedRows) unmatched, \(summary.skippedByManualConflict) skipped due to conflicts with manual data.",
                "Proceso completado: \(summary.linkedRows) filas enlazadas, \(summary.unmatchedRows) sin match, \(summary.skippedByManualConflict) omitidas por conflicto con datos manuales."
            )
    }

    private func optimizedImageData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let maxDimension: CGFloat = 640
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        let scale = min(1, maxDimension / max(width, height))
        let targetSize = CGSize(width: width * scale, height: height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resizedImage.jpegData(compressionQuality: 0.82)
    }
}

// MARK: - Preview

#Preview {
    UserDefaults.standard.set(AppAccessRole.owner.rawValue, forKey: "access.activeRole")

    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Land.self, LandHistoryEntry.self, LandGroup.self, LandTask.self, PendingSyncOperation.self,
        configurations: config
    )

    let auth = AuthViewModel()
    auth.accountEmail = "carlos@fincaolivo.es"

    return AccountView()
        .modelContainer(container)
        .environmentObject(auth)
        .environmentObject(RoleAccessViewModel())
}
