import Foundation

enum Config {
    // MARK: - Info.plist Access

    private static let infoPlist = Bundle.main.infoDictionary ?? [:]

    // MARK: - API Configuration

    /// Base URL for the viberunner API (from xcconfig via Info.plist)
    static var apiBaseURL: String {
        infoPlist["API_BASE_URL"] as? String ?? "http://localhost:3000"
    }

    // MARK: - Supabase Configuration

    /// Supabase project URL (from xcconfig via Info.plist)
    static var supabaseURL: String {
        infoPlist["SUPABASE_URL"] as? String ?? ""
    }

    /// Supabase anonymous key (from xcconfig via Info.plist)
    static var supabaseAnonKey: String {
        infoPlist["SUPABASE_ANON_KEY"] as? String ?? ""
    }

    /// Current environment name for debugging
    static var environmentName: String {
        if apiBaseURL.contains("localhost") || apiBaseURL.contains("192.168") {
            "Local"
        } else {
            "Production"
        }
    }

    // MARK: - GitHub OAuth

    /// GitHub OAuth callback scheme (for deep linking)
    static let githubOAuthScheme = "viberunner"

    /// GitHub OAuth callback host
    static let githubOAuthHost = "github-callback"

    /// Full callback URL for GitHub OAuth
    static var githubOAuthCallbackURL: String {
        "\(githubOAuthScheme)://\(githubOAuthHost)"
    }

    // MARK: - HR Configuration

    /// Default HR threshold in BPM
    static let defaultHRThreshold = 100

    /// Minimum allowed HR threshold
    static let minHRThreshold = 50

    /// Maximum allowed HR threshold
    static let maxHRThreshold = 220

    /// HR status poll interval in seconds
    static let hrStatusPollInterval: TimeInterval = 5.0
}
