import Foundation

enum SupabaseConfig {
    static let url = requiredURL(
        fullURLKey: "SUPABASE_URL",
        schemeKey: "SUPABASE_URL_SCHEME",
        hostKey: "SUPABASE_URL_HOST",
        portKey: "SUPABASE_URL_PORT"
    )
    static let anonKey = requiredString(for: "SUPABASE_ANON_KEY")
    static let emailConfirmationRedirectURL = optionalURL(for: "SUPABASE_EMAIL_CONFIRMATION_REDIRECT_URL")

    private static func requiredURL(fullURLKey: String, schemeKey: String, hostKey: String, portKey: String) -> URL {
        if let fullURL = optionalString(for: fullURLKey) {
            guard
                let url = URL(string: fullURL),
                let scheme = url.scheme,
                !scheme.isEmpty,
                let host = url.host,
                !host.isEmpty
            else {
                fatalError("Missing or invalid Supabase URL in build configuration.")
            }

            return url
        }

        guard
            let scheme = optionalString(for: schemeKey),
            let rawHost = optionalString(for: hostKey)
        else {
            fatalError("Missing Supabase URL components in build configuration.")
        }

        var components = URLComponents()
        components.scheme = scheme

        if let parsedHost = URLComponents(string: "\(scheme)://\(rawHost)") {
            components.host = parsedHost.host
            components.port = parsedHost.port
            if !parsedHost.path.isEmpty, parsedHost.path != "/" {
                components.path = parsedHost.path
            }
        } else {
            components.host = rawHost
        }

        if components.port == nil, let rawPort = optionalString(for: portKey) {
            guard let port = Int(rawPort) else {
                fatalError("Invalid \(portKey) in build configuration.")
            }
            components.port = port
        }

        guard let url = components.url else {
            fatalError("Missing or invalid Supabase URL in build configuration.")
        }
        return url
    }

    private static func requiredString(for key: String) -> String {
        guard let value = optionalString(for: key) else {
            fatalError("Missing \(key) in build configuration.")
        }
        return value
    }

    private static func optionalURL(for key: String) -> URL? {
        guard let value = optionalString(for: key) else { return nil }
        return URL(string: value)
    }

    private static func optionalString(for key: String) -> String? {
        let envValue = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let envValue, !envValue.isEmpty {
            return envValue
        }

        let plistValue = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let plistValue, !plistValue.isEmpty {
            return plistValue
        }

        return nil
    }
}
