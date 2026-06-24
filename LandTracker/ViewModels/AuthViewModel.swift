import Foundation
import Combine
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var mode: Mode = .login
    @Published var registrationType: RegistrationType = .individual
    @Published var userID: UUID?
    @Published var accountEmail = ""
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private var failedAuthAttempts = 0
    private var authBlockedUntil: Date?

    enum Mode {
        case login
        case register
    }

    enum RegistrationType: String, CaseIterable, Identifiable {
        case individual
        case organization
        case employee

        var id: String { rawValue }
    }

    private enum AuthSubmitError: LocalizedError {
        case employeeInvitationRequired

        var errorDescription: String? {
            switch self {
            case .employeeInvitationRequired:
                return "Este email no tiene una invitación pendiente. Pide al propietario que te invite primero."
            }
        }
    }

    private let service = SupabaseAuthService.shared

    func loadSession() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await service.currentSession()
            if let session, !session.isExpired {
                isAuthenticated = true
                userID = session.user.id
                accountEmail = session.user.email ?? ""
                if email.isEmpty {
                    email = accountEmail
                }
                await PushNotificationService.shared.syncDeviceTokenWithCloudIfPossible()
            } else {
                isAuthenticated = false
                userID = nil
                accountEmail = ""
            }
        } catch {
            isAuthenticated = false
            userID = nil
            accountEmail = ""
        }
    }

    func submit() async {
        if let blockedUntil = authBlockedUntil, blockedUntil > Date() {
            let secondsRemaining = max(1, Int(blockedUntil.timeIntervalSinceNow.rounded(.up)))
            errorMessage = "Demasiados intentos. Espera \(secondsRemaining) segundos antes de volver a intentarlo."
            successMessage = nil
            return
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Introduce email y contraseña."
            successMessage = nil
            return
        }

        email = normalizedEmail

        isLoading = true
        errorMessage = nil
        successMessage = nil
        defer { isLoading = false }
        do {
            var resultingSession: Session?

            switch mode {
            case .login:
                resultingSession = try await service.signIn(email: normalizedEmail, password: password)
            case .register:
                switch registrationType {
                case .individual:
                    let response = try await service.signUp(
                        email: normalizedEmail,
                        password: password,
                        accountType: .individual
                    )
                    resultingSession = response.session
                case .organization:
                    let response = try await service.signUp(
                        email: normalizedEmail,
                        password: password,
                        accountType: .organization
                    )
                    resultingSession = response.session
                case .employee:
                    let canRegister = try await service.canRegisterAsInvitedEmployee(email: normalizedEmail)
                    guard canRegister else {
                        throw AuthSubmitError.employeeInvitationRequired
                    }
                    let response = try await service.signUp(
                        email: normalizedEmail,
                        password: password,
                        accountType: .individual
                    )
                    resultingSession = response.session
                }

                if resultingSession == nil {
                    resetAuthGuard()
                    isAuthenticated = false
                    userID = nil
                    accountEmail = ""
                    password = ""
                    mode = .login
                    successMessage = "Por favor, confirme el email antes de iniciar sesión."
                    return
                }
            }

            let isValidSession = (resultingSession != nil && resultingSession?.isExpired == false)
            isAuthenticated = isValidSession
            userID = resultingSession?.user.id
            accountEmail = resultingSession?.user.email ?? normalizedEmail

            if isAuthenticated {
                resetAuthGuard()
                await PushNotificationService.shared.syncDeviceTokenWithCloudIfPossible()
            }
        } catch {
            registerFailedAuthAttempt()
            errorMessage = mappedAuthErrorMessage(from: error)
            successMessage = nil
            isAuthenticated = false
            userID = nil
            accountEmail = ""
        }
    }

    func signOut() async {
        await PushNotificationService.shared.removeDeviceTokenFromCloudIfPossible()
        do { try await service.signOut() } catch {}
        isAuthenticated = false
        userID = nil
        accountEmail = ""
        email = ""
        password = ""
        mode = .login
        registrationType = .individual
        errorMessage = nil
        successMessage = nil
        UserDefaults.standard.removeObject(forKey: AccountPreferences.accountTypeKey)
        ProfileImageStore.shared.imageData = nil
        resetAuthGuard()
    }

    private func registerFailedAuthAttempt() {
        failedAuthAttempts += 1
        if failedAuthAttempts >= 5 {
            authBlockedUntil = Date().addingTimeInterval(60)
            failedAuthAttempts = 0
        }
    }

    private func resetAuthGuard() {
        failedAuthAttempts = 0
        authBlockedUntil = nil
    }

    private func mappedAuthErrorMessage(from error: Error) -> String {
        let rawMessage = error.localizedDescription
        let normalizedMessage = rawMessage.lowercased()

        if normalizedMessage.contains("email not confirmed") || normalizedMessage.contains("email_not_confirmed") {
            return "Por favor, confirme el email antes de iniciar sesión."
        }

        if normalizedMessage.contains("rate limit")
            || normalizedMessage.contains("too many requests")
            || normalizedMessage.contains("429") {
            return "Se han detectado demasiados intentos. Inténtalo de nuevo en unos minutos."
        }

        if normalizedMessage.contains("invalid login credentials")
            || normalizedMessage.contains("invalid_credentials") {
            return "Email o contraseña incorrectos."
        }

        if normalizedMessage.contains("user already registered")
            || normalizedMessage.contains("already registered")
            || normalizedMessage.contains("already exists") {
            return "Este email ya está registrado."
        }

        if let submitError = error as? AuthSubmitError, let description = submitError.errorDescription {
            return description
        }

        return "No se pudo completar la operación. Inténtalo de nuevo."
    }
}
