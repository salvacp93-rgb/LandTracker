import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LandListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var roleAccessViewModel: RoleAccessViewModel
    @Query(sort: \Land.name) private var lands: [Land]
    @Query(sort: \LandGroup.name) private var groups: [LandGroup]
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue
    @State private var showingCreate = false
    @State private var showingAccount = false
    @State private var showingSettings = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportData: Data?
    @State private var ioError: String?
    @State private var searchText = ""

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private let neutralTint = Color(red: 0.55, green: 0.60, blue: 0.68)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if filteredLands.isEmpty {
                        GlassPanelCard(
                            title: lands.isEmpty
                                ? language.localized("No lands yet", "Todavía no hay terrenos")
                                : language.localized("No matching lands", "No hay terrenos que coincidan"),
                            subtitle: lands.isEmpty
                                ? language.localized("Create your first land to start working with maps, devices and grouped structure.", "Crea tu primer terreno para empezar a trabajar con mapas, dispositivos y estructura agrupada.")
                                : language.localized("Try another search term or clear the filter to see all your lands again.", "Prueba otro término o limpia la búsqueda para volver a ver todos tus terrenos."),
                            systemImage: "leaf.circle.fill",
                            tint: neutralTint
                        ) {
                            if lands.isEmpty && roleAccessViewModel.canManageStructure {
                                Button {
                                    showingCreate = true
                                } label: {
                                    Label(language.localized("Create land", "Crear terreno"), systemImage: "plus.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(neutralTint)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredLands) { land in
                                NavigationLink(value: land) {
                                    LandOverviewCard(
                                        land: land,
                                        language: language,
                                        canManageStructure: roleAccessViewModel.canManageStructure,
                                        onDelete: {
                                            deleteLand(land)
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(language.localized("My Lands", "Mis terrenos"))
            .searchable(text: $searchText, prompt: language.localized("Search lands", "Buscar terrenos"))
            .navigationDestination(for: Land.self) { land in
                LandDetailView(land: land)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    SettingsToolbarButton {
                        showingSettings = true
                    }

                    AccountToolbarButton {
                        showingAccount = true
                    }

                    if roleAccessViewModel.canManageStructure {
                        Menu {
                            Button("Export JSON") {
                                do {
                                    exportData = try ImportExportService.exportData(lands: lands, groups: groups)
                                    showingExporter = true
                                } catch {
                                    ioError = error.localizedDescription
                                }
                            }
                            Button("Import JSON") {
                                showingImporter = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }

                if roleAccessViewModel.canManageStructure {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingCreate = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAccount) {
                NavigationStack {
                    AccountView()
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .sheet(isPresented: $showingCreate) {
                LandEditorView(mode: .create)
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: ExportDocument(data: exportData ?? Data()),
                contentType: .json,
                defaultFilename: "LandTracker-Export"
            ) { result in
                if case .failure(let error) = result {
                    ioError = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                do {
                    let url = try result.get()
                    let data = try Data(contentsOf: url)
                    try ImportExportService.importData(data, context: context)
                    try? context.save()
                    Task { @MainActor in
                        let importedTasks = (try? context.fetch(FetchDescriptor<LandTask>())) ?? []
                        await TaskReminderService.shared.syncReminders(for: importedTasks, language: language)
                        await SupabaseSyncService.shared.queueAllLocalDataForSync(context: context)
                    }
                } catch {
                    ioError = error.localizedDescription
                }
            }
            .alert("Import/Export Error", isPresented: Binding(get: { ioError != nil }, set: { _ in ioError = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(ioError ?? "")
            }
        }
    }

    private var filteredLands: [Land] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return lands }

        return lands.filter { land in
            let localizedActivity = ActivityCatalog.displayName(for: land.activityType, language: language)
            let localizedProduction = ProductionCatalog.displayName(for: land.productionType, language: language)
            let localizedSubtype = ProductionCatalog.displayVarietyName(for: land.productionSubtype, language: language)
            return land.name.localizedCaseInsensitiveContains(trimmed) ||
                land.activityType.localizedCaseInsensitiveContains(trimmed) ||
                localizedActivity.localizedCaseInsensitiveContains(trimmed) ||
                land.productionType.localizedCaseInsensitiveContains(trimmed) ||
                localizedProduction.localizedCaseInsensitiveContains(trimmed) ||
                land.productionSubtype.localizedCaseInsensitiveContains(trimmed) ||
                localizedSubtype.localizedCaseInsensitiveContains(trimmed) ||
                land.notes.localizedCaseInsensitiveContains(trimmed) ||
                (land.group?.name.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private func deleteLand(_ land: Land) {
        guard roleAccessViewModel.canManageStructure else { return }
        let id = land.id
        context.delete(land)
        try? context.save()
        Task { @MainActor in
            await SupabaseSyncService.shared.queueLandDelete(id: id, context: context)
        }
    }
}

private struct LandOverviewCard: View {
    let land: Land
    let language: AppLanguage
    let canManageStructure: Bool
    let onDelete: () -> Void

    var body: some View {
        MonochromeGlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(land.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(land.group?.name ?? language.localized("Ungrouped", "Sin grupo"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contextMenu {
            if canManageStructure {
                Button(role: .destructive, action: onDelete) {
                    Label(language.localized("Delete land", "Eliminar terreno"), systemImage: "trash")
                }
            }
        }
    }
}

private struct MonochromeGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
            )
    }
}

private struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
