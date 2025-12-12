import Foundation
import Supabase

/// Service for handling Supabase authentication
class AuthService: ObservableObject {
    static let shared = AuthService()

    private let supabase: SupabaseClient

    @Published var currentUser: User?
    @Published var currentSession: Session?
    @Published var isAuthenticated: Bool = false

    private init() {
        // Initialize Supabase client
        // These values should be stored in a config file or environment
        let supabaseURL = URL(string: Configuration.supabaseURL)!
        let supabaseKey = Configuration.supabaseAnonKey

        self.supabase = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey
        )

        // Listen for auth state changes
        Task {
            await listenToAuthChanges()
        }
    }

    /// Get the current access token for API calls
    var accessToken: String? {
        currentSession?.accessToken
    }

    /// Get the Supabase client for direct access
    var client: SupabaseClient {
        supabase
    }

    // MARK: - Auth State

    private func listenToAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            await MainActor.run {
                self.currentSession = session
                self.currentUser = session?.user
                self.isAuthenticated = session != nil
            }

            switch event {
            case .signedIn:
                print("User signed in: \(session?.user.email ?? "unknown")")
            case .signedOut:
                print("User signed out")
            case .tokenRefreshed:
                print("Token refreshed")
            default:
                break
            }
        }
    }

    /// Check if we have an existing session
    func checkSession() async throws {
        let session = try await supabase.auth.session
        await MainActor.run {
            self.currentSession = session
            self.currentUser = session.user
            self.isAuthenticated = true
        }
    }

    // MARK: - Email Auth

    /// Sign up with email and password
    func signUp(email: String, password: String) async throws {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password
        )

        await MainActor.run {
            self.currentSession = response.session
            self.currentUser = response.user
            self.isAuthenticated = response.session != nil
        }
    }

    /// Sign in with email and password
    func signIn(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(
            email: email,
            password: password
        )

        await MainActor.run {
            self.currentSession = session
            self.currentUser = session.user
            self.isAuthenticated = true
        }
    }

    /// Sign in with magic link (passwordless)
    func signInWithMagicLink(email: String) async throws {
        try await supabase.auth.signInWithOTP(
            email: email,
            redirectTo: URL(string: "viberunner://auth/callback")
        )
    }

    // MARK: - OAuth

    /// Sign in with Apple
    func signInWithApple() async throws {
        let session = try await supabase.auth.signInWithOAuth(
            provider: .apple,
            redirectTo: URL(string: "viberunner://auth/callback")
        )
        // OAuth flow will open a browser/sheet
    }

    /// Handle OAuth callback URL
    func handleOAuthCallback(url: URL) async throws {
        let session = try await supabase.auth.session(from: url)
        await MainActor.run {
            self.currentSession = session
            self.currentUser = session.user
            self.isAuthenticated = true
        }
    }

    // MARK: - Sign Out

    /// Sign out the current user
    func signOut() async throws {
        try await supabase.auth.signOut()
        await MainActor.run {
            self.currentSession = nil
            self.currentUser = nil
            self.isAuthenticated = false
        }
    }

    // MARK: - Password Reset

    /// Send password reset email
    func resetPassword(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }

    /// Update password (when logged in or with reset token)
    func updatePassword(newPassword: String) async throws {
        try await supabase.auth.update(user: UserAttributes(password: newPassword))
    }
}

// MARK: - Configuration

enum Configuration {
    // These should be replaced with actual values from your Supabase project
    // In production, use a config file or environment variables

    static var supabaseURL: String {
        // Try to get from Info.plist or use default
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
            ?? "https://your-project.supabase.co"
    }

    static var supabaseAnonKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
            ?? "your-anon-key"
    }

    static var apiBaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "http://localhost:3000"
    }
}
