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
}
