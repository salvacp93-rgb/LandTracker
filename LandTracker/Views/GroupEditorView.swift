import SwiftUI
import SwiftData

struct GroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue

    @State private var name: String = ""
    @State private var colorHex: String = GroupColorPalette.hexValues.first ?? "2D9CDB"

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var selectedColor: Color {
        Color(hex: colorHex)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    GlassPanelCard(
                        title: language.localized("Group name", "Nombre del grupo"),
                        subtitle: language.localized("Use a short, easy-to-recognize name to organize your lands.", "Escribe un nombre corto y fácil de reconocer para organizar tus terrenos."),
                        systemImage: "character.textbox",
                        tint: selectedColor
                    ) {
                        groupEditorFieldShell(
                            label: language.localized("Name", "Nombre"),
                            systemImage: "textformat",
                            tint: selectedColor
                        ) {
                            TextField(
                                language.localized("Example: North fields", "Ejemplo: Campos norte"),
                                text: $name
                            )
                            .textInputAutocapitalization(.words)
                        }
                    }

                    GlassPanelCard(
                        title: language.localized("Color", "Color"),
                        subtitle: language.localized("Select the color that will identify this group across the app and on the map.", "Selecciona el color que identificará al grupo en la app y en el mapa."),
                        systemImage: "paintpalette.fill",
                        tint: selectedColor
                    ) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 12)], spacing: 12) {
                            ForEach(GroupColorPalette.hexValues, id: \.self) { hex in
                                GroupColorChoiceCard(
                                    color: Color(hex: hex),
                                    isSelected: colorHex == hex,
                                    selectedLabel: language.localized("Selected", "Seleccionado")
                                ) {
                                    colorHex = hex
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selectedColor)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(selectedColor.opacity(0.18), lineWidth: 1)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.localized("Current color", "Color actual"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text("#" + colorHex)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(language.localized("New Group", "Nuevo grupo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(language.localized("Cancel", "Cancelar")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.localized("Save", "Guardar")) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private func groupEditorFieldShell<Content: View>(
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

    private func save() {
        let group = LandGroup(name: trimmedName, colorHex: colorHex)
        context.insert(group)
        try? context.save()
        Task { @MainActor in
            await SupabaseSyncService.shared.queueGroupUpsert(id: group.id, context: context)
        }
        dismiss()
    }
}

private struct GroupColorChoiceCard: View {
    let color: Color
    let isSelected: Bool
    let selectedLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.78), lineWidth: 1.5)
                    )

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? color : .secondary)

                Text(isSelected ? selectedLabel : " ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSelected ? 0.24 : 0.1),
                                color.opacity(isSelected ? 0.2 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? color.opacity(0.34) : Color.white.opacity(0.18),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
