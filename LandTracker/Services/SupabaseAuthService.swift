import Foundation
import Supabase

final class SupabaseAuthService {
    static let shared = SupabaseAuthService()
    let client: SupabaseClient

    enum AccountType: String {
        case individual
        case organization
    }

    private init() {
        let options = SupabaseClientOptions(
            auth: .init(
                emitLocalSessionAsInitialSession: true
            )
        )
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: options
        )
    }

    func currentSession() async throws -> Session? {
        try await client.auth.session
    }

    func signIn(email: String, password: String) async throws -> Session {
        try await client.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String, accountType: AccountType? = nil) async throws -> AuthResponse {
        let metadata: [String: AnyJSON]?
        if let accountType {
            metadata = ["account_type": .string(accountType.rawValue)]
        } else {
            metadata = nil
        }

        return try await client.auth.signUp(
            email: email,
            password: password,
            data: metadata,
            redirectTo: SupabaseConfig.emailConfirmationRedirectURL
        )
    }

    func canRegisterAsInvitedEmployee(email: String) async throws -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else { return false }

        let isInvited: Bool = try await client
            .rpc("can_register_employee", params: ["p_email": normalizedEmail])
            .execute()
            .value
        return isInvited
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: Password recovery

    /// Asks Supabase to email a reset link. Supabase answers the same way whether or not the
    /// account exists, so callers must not treat success as proof that it does.
    func sendPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(
            email,
            redirectTo: SupabaseConfig.passwordResetRedirectURL
        )
    }

    /// Turns the link that opened the app into a (recovery) session. The URL carries a one-time
    /// code or token: never log it.
    @discardableResult
    func session(from url: URL) async throws -> Session {
        try await client.auth.session(from: url)
    }

    func updatePassword(_ newPassword: String) async throws {
        _ = try await client.auth.update(user: UserAttributes(password: newPassword))
    }

    /// Revokes every session of the user except this device's.
    func signOutOtherSessions() async throws {
        try await client.auth.signOut(scope: .others)
    }

    /// Ends only this device's session, leaving the user's other devices signed in.
    func signOutCurrentSession() async throws {
        try await client.auth.signOut(scope: .local)
    }
}
