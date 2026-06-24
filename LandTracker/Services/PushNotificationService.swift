import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationService {
    static let shared = PushNotificationService()

    private let defaults = UserDefaults.standard

    private init() {}

    var currentDeviceToken: String? {
        let token = defaults.string(forKey: AccountPreferences.pushDeviceTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty else { return nil }
        return token
    }

    func ensureRemoteRegistration() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func requestAuthorizationAndRegisterIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .ephemeral, .provisional:
            ensureRemoteRegistration()
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if granted {
                ensureRemoteRegistration()
            }
        case .denied:
            break
        @unknown default:
            break
        }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(token, forKey: AccountPreferences.pushDeviceTokenKey)

        Task {
            await syncDeviceTokenWithCloudIfPossible()
        }
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        #if DEBUG
        print("APNs register failed: \(error.localizedDescription)")
        #endif
    }

    func syncDeviceTokenWithCloudIfPossible() async {
        guard let token = currentDeviceToken else { return }
        try? await SupabaseSyncService.shared.upsertPushDeviceToken(token)
    }

    func removeDeviceTokenFromCloudIfPossible() async {
        guard let token = currentDeviceToken else { return }
        try? await SupabaseSyncService.shared.deletePushDeviceToken(token)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            PushNotificationService.shared.ensureRemoteRegistration()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
