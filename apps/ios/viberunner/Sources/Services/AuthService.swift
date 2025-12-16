import Foundation
import UIKit
import Supabase
import AuthenticationServices
import os.log

private let logger = Logger(subsystem: "com.viberunner.app", category: "AuthService")

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var error: String?

    private var supabase: SupabaseClient?

    private init() {
        setupSupabase()
        Task {
            await checkSession()
        }
    }

    private func setupSupabase() {
        logger.info("setupSupabase called")
        logger.debug("Config.supabaseURL: '\(Config.supabaseURL)'")
        logger.debug("Config.supabaseAnonKey: '\(String(Config.supabaseAnonKey.prefix(20)))...'")

        guard !Config.supabaseURL.isEmpty, !Config.supabaseAnonKey.isEmpty else {
            logger.error("Supabase configuration missing!")
            return
        }

        supabase = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
        logger.info("Supabase client initialized successfully")
    }

    // MARK: - Session Management

    func checkSession() async {
        guard let supabase = supabase else { return }

        do {
            let session = try await supabase.auth.session
            currentUser = session.user
            isAuthenticated = true
        } catch {
            currentUser = nil
            isAuthenticated = false
        }
    }

    var accessToken: String? {
        get async {
            guard let supabase = supabase else { return nil }
            do {
                let session = try await supabase.auth.session
                return session.accessToken
            } catch {
                return nil
            }
        }
    }

    // MARK: - GitHub Sign In

    func signInWithGitHub() async throws {
        logger.info("signInWithGitHub called")
        logger.debug("Supabase URL: \(Config.supabaseURL)")

        guard let supabase = supabase else {
            logger.error("Supabase not configured")
            self.error = "Supabase not configured. Check your settings."
            throw AuthError.notConfigured
        }

        isLoading = true
        error = nil

        do {
            logger.info("Starting OAuth flow with ASWebAuthenticationSession...")
            // Request repo scope so we can create/manage repos without separate OAuth
            let session = try await supabase.auth.signInWithOAuth(
                provider: .github,
                redirectTo: URL(string: Config.githubOAuthCallbackURL),
                scopes: "repo read:user user:email"
            ) { (session: ASWebAuthenticationSession) in
                session.prefersEphemeralWebBrowserSession = false
            }
            logger.info("OAuth completed successfully, user: \(session.user.email ?? "no email")")
            currentUser = session.user
            isAuthenticated = true
            isLoading = false

            // Sync GitHub token to backend for repo operations
            if let providerToken = session.providerToken {
                logger.info("Provider token available, syncing to backend...")
                await syncGitHubToken(providerToken: providerToken)
            } else {
                logger.warning("No provider token returned from OAuth")
            }
        } catch {
            logger.error("OAuth error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            isLoading = false
            throw error
        }
    }

    /// Sync GitHub provider token to backend for repo operations
    private func syncGitHubToken(providerToken: String) async {
        do {
            try await APIService.shared.syncGitHubToken(providerToken: providerToken)
            logger.info("GitHub token synced successfully")
        } catch {
            logger.error("Failed to sync GitHub token: \(error.localizedDescription)")
            // Don't fail the sign-in, user can still use the app
        }
    }

    // Keep for backward compatibility if needed for deep link handling
    func handleOAuthCallback(url: URL) async throws {
        logger.info("handleOAuthCallback called with URL: \(url)")
        guard let supabase = supabase else {
            throw AuthError.notConfigured
        }

        isLoading = true
        error = nil

        do {
            let session = try await supabase.auth.session(from: url)
            currentUser = session.user
            isAuthenticated = true
            isLoading = false
            logger.info("OAuth callback handled successfully")
        } catch {
            logger.error("OAuth callback error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            isLoading = false
            throw error
        }
    }

    // MARK: - Email/Password Auth

    func signIn(email: String, password: String) async throws {
        guard let supabase = supabase else {
            throw AuthError.notConfigured
        }

        isLoading = true
        error = nil

        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            currentUser = session.user
            isAuthenticated = true
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            throw error
        }
    }

    func signUp(email: String, password: String) async throws {
        guard let supabase = supabase else {
            throw AuthError.notConfigured
        }

        isLoading = true
        error = nil

        do {
            let result = try await supabase.auth.signUp(email: email, password: password)
            if let session = result.session {
                currentUser = session.user
                isAuthenticated = true
            }
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            throw error
        }
    }

    // MARK: - Sign Out

    func signOut() async throws {
        guard let supabase = supabase else {
            throw AuthError.notConfigured
        }

        do {
            try await supabase.auth.signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notConfigured
    case invalidCredentials
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Authentication is not configured"
        case .invalidCredentials:
            return "Invalid email or password"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
