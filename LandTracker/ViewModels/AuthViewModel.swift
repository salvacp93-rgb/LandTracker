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
    /// True from the moment a valid reset link is opened until the user saves a new password (or
    /// cancels). While true the app must not treat the recovery session as a normal sign-in.
    @Published var isSettingNewPassword = false
    /// Localized message shown when an incoming auth link is expired, used or invalid.
    @Published var authLinkError: String?
    @Published var isSendingPasswordReset = false
    @Published var isUpdatingPassword = false
    /// When the next reset email may be requested. Kept here (not in the sheet) so closing and
    /// reopening the sheet cannot bypass it: every request rewrites the SDK's single PKCE code
    /// verifier, which kills the link of the email sent before.
    @Published private(set) var passwordResetAvailableAt: Date?
    /// Set when signing out the user's other devices failed after a password reset.
    @Published var otherSessionsNotice: String?

    /// Minimum length enforced before calling Supabase (its default). The server stays the authority.
    static let minimumPasswordLength = 6
    /// Supabase allows one recovery email per user per minute.
    static let passwordResetCooldown: TimeInterval = 60

    /// Plain flags only: no URL, token or code is ever persisted.
    private static let pendingRecoveryKey = "auth.pendingPasswordRecovery"
    private static let resetAvailableAtKey = "auth.passwordResetAvailableAt"

    enum PasswordResetRequestResult: Equatable {
        /// The request went through. Says nothing about whether the account exists.
        case sent(email: String)
        case failed(message: String)
    }

    private var failedAuthAttempts = 0
    private var authBlockedUntil: Date?
    private var isExchangingRecoveryLink = false

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

    init() {
        let stored = UserDefaults.standard.double(forKey: Self.resetAvailableAtKey)
        if stored > 0 {
            let until = Date(timeIntervalSince1970: stored)
            // Ignore values from the past or implausibly far ahead (clock changes).
            if until > Date(), until <= Date().addingTimeInterval(Self.passwordResetCooldown) {
                passwordResetAvailableAt = until
            }
        }
    }

    func loadSession() async {
        // A recovery session is not a sign-in: the user has to choose a password first.
        guard !isPasswordRecoveryActive else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await service.currentSession()
            guard !isPasswordRecoveryActive else { return }
            if let session, !session.isExpired {
                if hasPendingPasswordRecovery {
                    // The app was closed while the "new password" sheet was up. The recovery
                    // session is still in the keychain, so ask for the password again instead of
                    // letting it pass as a normal sign-in.
                    isAuthenticated = false
                    userID = nil
                    accountEmail = ""
                    isSettingNewPassword = true
                    return
                }
                isAuthenticated = true
                userID = session.user.id
                accountEmail = session.user.email ?? ""
                if email.isEmpty {
                    email = accountEmail
                }
                await PushNotificationService.shared.syncDeviceTokenWithCloudIfPossible()
            } else {
                if session == nil {
                    // The recovery session is gone (revoked or signed out): nothing left to resume.
                    clearPendingPasswordRecovery()
                }
                isAuthenticated = false
                userID = nil
                accountEmail = ""
            }
        } catch {
            if !isNetworkError(error) {
                clearPendingPasswordRecovery()
            }
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
                // Signing in with the password supersedes any unfinished recovery.
                clearPendingPasswordRecovery()
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
        clearPendingPasswordRecovery()
        // A global sign-out already ended every other session.
        otherSessionsNotice = nil
    }

    // MARK: - Password recovery

    private var isPasswordRecoveryActive: Bool {
        isSettingNewPassword || isExchangingRecoveryLink
    }

    /// True between opening a valid reset link and choosing a password. Survives an app kill.
    private var hasPendingPasswordRecovery: Bool {
        UserDefaults.standard.bool(forKey: Self.pendingRecoveryKey)
    }

    private func markPasswordRecoveryPending() {
        UserDefaults.standard.set(true, forKey: Self.pendingRecoveryKey)
    }

    private func clearPendingPasswordRecovery() {
        UserDefaults.standard.removeObject(forKey: Self.pendingRecoveryKey)
    }

    /// Whole seconds left before another reset email may be requested (0 when free).
    var passwordResetCooldownRemaining: Int {
        guard let until = passwordResetAvailableAt else { return 0 }
        return max(0, Int(until.timeIntervalSinceNow.rounded(.up)))
    }

    private func startPasswordResetCooldown() {
        let until = Date().addingTimeInterval(Self.passwordResetCooldown)
        passwordResetAvailableAt = until
        UserDefaults.standard.set(until.timeIntervalSince1970, forKey: Self.resetAvailableAtKey)
    }

    /// Basic shape check only (something@domain.tld, no spaces). Supabase does the real validation.
    static func isPlausibleEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    /// Sends the reset email. Empty or malformed addresses are rejected without any request.
    ///
    /// Two rules keep this from leaking whether an account exists: the cooldown is global (it does
    /// not depend on the address), and an "email rate limit" answer from Supabase, which only
    /// happens for accounts that exist, is reported exactly like a successful send.
    func requestPasswordReset(email rawEmail: String) async -> PasswordResetRequestResult {
        guard !isSendingPasswordReset else {
            return .failed(message: localized("Sending the link. Please wait.", "Enviando el enlace. Espera un momento."))
        }

        guard Self.isPlausibleEmail(rawEmail) else {
            return .failed(message: localized("Enter a valid email address.", "Introduce un correo electrónico válido."))
        }

        let remaining = passwordResetCooldownRemaining
        guard remaining == 0 else {
            return .failed(
                message: localized(
                    "Wait \(remaining) seconds before asking for another link.",
                    "Espera \(remaining) segundos antes de pedir otro enlace."
                )
            )
        }

        let normalizedEmail = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        isSendingPasswordReset = true
        defer { isSendingPasswordReset = false }
        do {
            try await service.sendPasswordReset(email: normalizedEmail)
            startPasswordResetCooldown()
            return .sent(email: normalizedEmail)
        } catch {
            switch passwordResetRateLimit(from: error) {
            case .perAccount:
                startPasswordResetCooldown()
                return .sent(email: normalizedEmail)
            case .perClient:
                startPasswordResetCooldown()
                return .failed(message: passwordResetRateLimitMessage)
            case nil:
                return .failed(message: passwordResetErrorMessage(from: error))
            }
        }
    }

    /// Handles a link that opened the app. Only the password-reset link is accepted; anything else
    /// is ignored silently. The URL is never logged, stored or shown.
    func handleIncomingURL(_ url: URL) async {
        guard AppDeepLink.isPasswordResetURL(url) else { return }

        // The same link can arrive twice (one delivery per scene, or the user taps it again while
        // the "new password" sheet is up). A link is single use: a second exchange would fail and
        // raise a false "expired" alert over a valid reset.
        guard !isExchangingRecoveryLink, !isSettingNewPassword else { return }

        isExchangingRecoveryLink = true
        do {
            let session = try await service.session(from: url)
            isExchangingRecoveryLink = false
            // The SDK has stored the recovery session by now. Remember that it is not a sign-in.
            markPasswordRecoveryPending()

            // The link may belong to another account than the one signed in on this device. Drop the
            // previous account first so RootView clears its local cache and role state.
            if isAuthenticated, userID != session.user.id {
                isAuthenticated = false
                userID = nil
                accountEmail = ""
            }

            authLinkError = nil
            isSettingNewPassword = true
        } catch {
            isExchangingRecoveryLink = false
            authLinkError = localized(
                "This link has expired or is not valid. Request a new one from the login screen.",
                "Este enlace ha caducado o no es válido. Solicita uno nuevo desde la pantalla de inicio de sesión."
            )
            // A loadSession() that ran during the exchange was skipped; restore the normal state.
            await loadSession()
        }
    }

    /// First problem with the new password, or nil when it can be sent.
    func newPasswordValidationMessage(password: String, confirmation: String) -> String? {
        if password.count < Self.minimumPasswordLength {
            return passwordTooShortMessage
        }
        if password != confirmation {
            return localized("Passwords do not match.", "Las contraseñas no coinciden.")
        }
        return nil
    }

    /// Saves the new password. Returns nil on success (the app then opens signed in) or the
    /// message to show while the sheet stays up.
    func updatePassword(_ newPassword: String) async -> String? {
        guard !isUpdatingPassword else { return nil }
        guard newPassword.count >= Self.minimumPasswordLength else {
            return passwordTooShortMessage
        }

        isUpdatingPassword = true
        defer { isUpdatingPassword = false }
        do {
            try await service.updatePassword(newPassword)
        } catch {
            return passwordUpdateErrorMessage(from: error)
        }

        // The password is chosen: the recovery is over even if the app is closed from here on.
        clearPendingPasswordRecovery()

        // Anyone else holding an old session for this account (the reason people reset a password)
        // gets signed out. The password is already changed, so a failure does not undo it, but the
        // user is told instead of assuming it worked.
        let revokedOtherSessions = await revokeOtherSessions()

        isSettingNewPassword = false
        errorMessage = nil
        successMessage = nil
        resetAuthGuard()
        await loadSession()
        if !isAuthenticated {
            successMessage = localized(
                "Password updated. Sign in with your new password.",
                "Contraseña actualizada. Inicia sesión con tu contraseña nueva."
            )
        }
        if !revokedOtherSessions {
            otherSessionsNotice = otherSessionsFailureMessage
        }
        return nil
    }

    /// Signs out every other device. Tries twice: one network blip must not leave old sessions alive.
    private func revokeOtherSessions() async -> Bool {
        for _ in 0..<2 {
            do {
                try await service.signOutOtherSessions()
                return true
            } catch {
                continue
            }
        }
        return false
    }

    /// Retry offered from the notice shown when signing out the other devices failed.
    func retrySignOutOfOtherSessions() async {
        otherSessionsNotice = nil
        if !(await revokeOtherSessions()) {
            otherSessionsNotice = otherSessionsFailureMessage
        }
    }

    /// Abandons the recovery: ends the temporary session on this device only and returns to login.
    func cancelPasswordRecovery() async {
        isSettingNewPassword = false
        if isAuthenticated {
            await PushNotificationService.shared.removeDeviceTokenFromCloudIfPossible()
        }
        // The SDK drops the local session before it contacts the server, so a network failure here
        // still leaves this device signed out.
        do { try await service.signOutCurrentSession() } catch {}
        clearPendingPasswordRecovery()
        isAuthenticated = false
        userID = nil
        accountEmail = ""
        password = ""
        mode = .login
        registrationType = .individual
        errorMessage = nil
        successMessage = nil
        UserDefaults.standard.removeObject(forKey: AccountPreferences.accountTypeKey)
        resetAuthGuard()
    }

    private enum PasswordResetRateLimit {
        /// Supabase limits the mail for one address. Only accounts that exist ever get this answer,
        /// so it must not be shown as an error.
        case perAccount
        /// Limit on the caller (IP), independent of the address: safe to show.
        case perClient
    }

    private func passwordResetRateLimit(from error: Error) -> PasswordResetRateLimit? {
        if isNetworkError(error) { return nil }

        if let authError = error as? AuthError {
            switch authError.errorCode.rawValue {
            case "over_request_rate_limit":
                return .perClient
            case "over_email_send_rate_limit":
                return .perAccount
            default:
                break
            }
            if case let .api(_, _, _, response) = authError, response.statusCode == 429 {
                return .perAccount
            }
        }

        let normalizedMessage = error.localizedDescription.lowercased()
        if normalizedMessage.contains("rate limit") || normalizedMessage.contains("too many requests") {
            return .perAccount
        }
        return nil
    }

    private func passwordResetErrorMessage(from error: Error) -> String {
        if isNetworkError(error) {
            return networkErrorMessage
        }

        if let authError = error as? AuthError {
            switch authError.errorCode.rawValue {
            case "email_address_invalid", "validation_failed":
                return localized("Enter a valid email address.", "Introduce un correo electrónico válido.")
            default:
                break
            }
        }

        return localized(
            "We could not send the link. Try again in a few minutes.",
            "No hemos podido enviar el enlace. Inténtalo de nuevo en unos minutos."
        )
    }

    private func passwordUpdateErrorMessage(from error: Error) -> String {
        if isNetworkError(error) {
            return networkErrorMessage
        }

        let expiredSessionMessage = localized(
            "This session has expired. Cancel and request a new link from the login screen.",
            "Esta sesión ha caducado. Cancela y solicita un enlace nuevo desde la pantalla de inicio de sesión."
        )

        if let authError = error as? AuthError {
            switch authError {
            case .weakPassword:
                return weakPasswordMessage
            case .sessionMissing:
                return expiredSessionMessage
            default:
                break
            }

            switch authError.errorCode.rawValue {
            case "weak_password":
                return weakPasswordMessage
            case "same_password":
                return localized(
                    "The new password must be different from your current one.",
                    "La nueva contraseña debe ser distinta de la actual."
                )
            case "session_not_found", "bad_jwt", "invalid_jwt", "no_authorization", "user_not_found":
                return expiredSessionMessage
            case "over_request_rate_limit":
                return localized(
                    "Too many attempts. Wait a minute and try again.",
                    "Demasiados intentos. Espera un minuto e inténtalo de nuevo."
                )
            default:
                break
            }
        }

        return localized(
            "We could not save your password. Try again.",
            "No hemos podido guardar la contraseña. Inténtalo de nuevo."
        )
    }

    private var passwordTooShortMessage: String {
        let minimum = Self.minimumPasswordLength
        return localized(
            "Use at least \(minimum) characters.",
            "Usa al menos \(minimum) caracteres."
        )
    }

    private var weakPasswordMessage: String {
        localized(
            "This password is too weak. Try a longer one or mix letters, numbers and symbols.",
            "Esta contraseña es demasiado débil. Prueba con una más larga o combina letras, números y símbolos."
        )
    }

    private var passwordResetRateLimitMessage: String {
        localized(
            "Too many requests. Wait a minute before asking for another link.",
            "Demasiadas solicitudes. Espera un minuto antes de pedir otro enlace."
        )
    }

    private var otherSessionsFailureMessage: String {
        localized(
            "Your password was updated, but we could not sign out your other devices. Try again, or sign out from Account and sign back in.",
            "Tu contraseña se ha actualizado, pero no hemos podido cerrar la sesión en tus otros dispositivos. Inténtalo de nuevo o cierra sesión desde Cuenta y vuelve a entrar."
        )
    }

    private var networkErrorMessage: String {
        localized(
            "No connection. Check your internet and try again.",
            "Sin conexión. Comprueba tu conexión a internet e inténtalo de nuevo."
        )
    }

    private func isNetworkError(_ error: Error) -> Bool {
        error is URLError || (error as NSError).domain == NSURLErrorDomain
    }

    /// The view model has no language property: read the same stored setting the views use.
    private func localized(_ english: String, _ spanish: String) -> String {
        let raw = UserDefaults.standard.string(forKey: AccountPreferences.appLanguageKey)
            ?? AppSettings.defaultLanguage.rawValue
        return AppSettings.language(from: raw).localized(english, spanish)
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
