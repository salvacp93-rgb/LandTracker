import SwiftUI
import SwiftData

struct LandTaskEditorView: View {
    enum Mode {
        case create(Land)
        case edit(LandTask)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(AccountPreferences.appLanguageKey) private var appLanguageRaw = AppSettings.defaultLanguage.rawValue

    private let mode: Mode

    @State private var type: LandTaskType
    @State private var title: String
    @State private var dueDate: Date
    @State private var wantsReminder: Bool
    @State private var reminderDate: Date
    @State private var notes: String

    init(mode: Mode) {
        self.mode = mode
        let defaultDueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

        switch mode {
        case .create:
            _type = State(initialValue: .irrigation)
            _title = State(initialValue: "")
            _dueDate = State(initialValue: defaultDueDate)
            _wantsReminder = State(initialValue: false)
            _reminderDate = State(initialValue: defaultDueDate)
            _notes = State(initialValue: "")
        case .edit(let task):
            _type = State(initialValue: task.type)
            _title = State(initialValue: task.title)
            _dueDate = State(initialValue: task.dueDate)
            _wantsReminder = State(initialValue: task.reminderDate != nil)
            _reminderDate = State(initialValue: task.reminderDate ?? task.dueDate)
            _notes = State(initialValue: task.notes)
        }
    }

    private var language: AppLanguage {
        AppSettings.language(from: appLanguageRaw)
    }

    private var canSave: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == .other {
            return !trimmedTitle.isEmpty
        }
        return true
    }

    private var resolvedTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? type.displayName(language: language) : trimmedTitle
    }

    private var screenTitle: String {
        switch mode {
        case .create:
            return language.localized("New Task", "Nueva tarea")
        case .edit:
            return language.localized("Edit Task", "Editar tarea")
        }
    }

    var body: some View {
        Form {
            Section(language.localized("Task", "Tarea")) {
                Picker(language.localized("Type", "Tipo"), selection: $type) {
                    ForEach(LandTaskType.allCases) { value in
                        Label(value.displayName(language: language), systemImage: value.symbolName)
                            .tag(value)
                    }
                }

                TextField(language.localized("Title", "Título"), text: $title, prompt: Text(type.displayName(language: language)))
            }

            Section(language.localized("Schedule", "Planificación")) {
                DatePicker(
                    language.localized("Due Date", "Fecha objetivo"),
                    selection: $dueDate,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Toggle(language.localized("Reminder", "Recordatorio"), isOn: $wantsReminder)

                if wantsReminder {
                    DatePicker(
                        language.localized("Remind Me At", "Recordarme en"),
                        selection: $reminderDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }

            Section(language.localized("Notes", "Notas")) {
                TextEditor(text: $notes)
                    .frame(minHeight: 110)
            }
        }
        .navigationTitle(screenTitle)
        .onChange(of: dueDate) { _, newValue in
            guard wantsReminder else { return }
            if reminderDate > newValue {
                reminderDate = newValue
            }
        }
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

    private func save() {
        let safeReminderDate = wantsReminder ? min(reminderDate, dueDate) : nil
        let safeNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        var taskForReminder: LandTask?
        var taskID: UUID?
        var landID: UUID?
        var landName: String?

        switch mode {
        case .create(let land):
            let task = LandTask(
                type: type,
                title: resolvedTitle,
                dueDate: dueDate,
                reminderDate: safeReminderDate,
                notes: safeNotes,
                land: land
            )
            context.insert(task)
            land.touchUpdatedAt()
            taskForReminder = task
            taskID = task.id
            landID = land.id
            landName = land.name

        case .edit(let task):
            task.type = type
            task.title = resolvedTitle
            task.dueDate = dueDate
            task.reminderDate = safeReminderDate
            task.notes = safeNotes
            task.touchUpdatedAt()

            if let land = task.land {
                land.touchUpdatedAt()
                landID = land.id
                landName = land.name
            }
            taskForReminder = task
            taskID = task.id
        }

        try? context.save()

        if let taskForReminder {
            Task { @MainActor in
                await TaskReminderService.shared.upsertReminder(
                    for: taskForReminder,
                    landName: landName,
                    language: language
                )
                if let taskID {
                    await SupabaseSyncService.shared.queueTaskUpsert(id: taskID, context: context)
                }
                if let landID {
                    await SupabaseSyncService.shared.queueLandUpsert(id: landID, context: context)
                }
            }
        }

        dismiss()
    }
}
