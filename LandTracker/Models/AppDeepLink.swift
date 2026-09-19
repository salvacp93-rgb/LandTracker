import Foundation

/// Custom URL scheme the app accepts from the outside (the password-reset email link).
///
/// The scheme must stay in sync with `CFBundleURLTypes` in `Config/AppInfo.plist`, and the full
/// redirect URL (`landtracker://reset-password`) must be listed under Supabase Dashboard >
/// Authentication > URL Configuration > Redirect URLs.
enum AppDeepLink {
    static let scheme = "landtracker"
    static let passwordResetHost = "reset-password"

    /// True only for `landtracker://reset-password...`. Anything else is not ours to handle.
    static func isPasswordResetURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme else { return false }
        return url.host?.lowercased() == passwordResetHost
    }
}
