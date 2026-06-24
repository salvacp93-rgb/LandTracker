import Foundation
import UserNotifications

final class TaskReminderService {
    static let shared = TaskReminderService()
    private static let identifierPrefix = "landtask."

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func cancelReminder(taskID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: taskID)])
    }

    func clearAllTaskReminders() {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.identifierPrefix) }
            guard !identifiers.isEmpty else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func syncReminders(for tasks: [LandTask], language: AppLanguage) async {
        let expectedIdentifiers = Set(tasks.map { notificationIdentifier(for: $0.id) })
        let pendingLandTaskIdentifiers = await pendingTaskNotificationIdentifiers()

        let staleIdentifiers = pendingLandTaskIdentifiers.filter { !expectedIdentifiers.contains($0) }
        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
        }

        guard await requestAuthorizationIfNeeded() else {
            return
        }

        for task in tasks {
            await scheduleReminderIfNeeded(for: task, landName: task.land?.name, language: language)
        }
    }

    func upsertReminder(for task: LandTask, landName: String?, language: AppLanguage) async {
        guard await requestAuthorizationIfNeeded() else { return }
        await scheduleReminderIfNeeded(for: task, landName: landName, language: language)
    }

    private func scheduleReminderIfNeeded(for task: LandTask, landName: String?, language: AppLanguage) async {
        cancelReminder(taskID: task.id)

        guard !task.isCompleted else { return }
        guard let reminderDate = task.reminderDate else { return }
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.sound = .default

        var bodyParts: [String] = []
        if let landName, !landName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyParts.append(landName)
        }
        bodyParts.append("\(language.localized("Due", "Vence")) \(task.dueDate.formatted(date: .abbreviated, time: .shortened))")
        content.body = bodyParts.joined(separator: " - ")

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminderDate
            ),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: task.id),
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    private func notificationIdentifier(for taskID: UUID) -> String {
        "\(Self.identifierPrefix)\(taskID.uuidString)"
    }

    private func pendingTaskNotificationIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests
                    .map(\.identifier)
                    .filter { $0.hasPrefix(Self.identifierPrefix) })
            }
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral, .provisional:
            await MainActor.run {
                PushNotificationService.shared.ensureRemoteRegistration()
            }
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if granted {
                await MainActor.run {
                    PushNotificationService.shared.ensureRemoteRegistration()
                }
            }
            return granted
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
