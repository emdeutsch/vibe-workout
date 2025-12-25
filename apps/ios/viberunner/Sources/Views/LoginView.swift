import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.viberunner.app", category: "LoginView")

struct LoginView: View {
    @EnvironmentObject var authService: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    // Animation states
    @State private var logoAppeared = false
    @State private var contentAppeared = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Subtle gradient background
                backgroundGradient

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Spacing.xl) {
                        Spacer()
                            .frame(height: geometry.size.height * 0.06)

                        // Logo section with animation
                        logoSection
                            .opacity(logoAppeared ? 1 : 0)
                            .offset(y: logoAppeared ? 0 : -20)

                        Spacer()
                            .frame(height: Spacing.xl)

                        // Auth section
                        authSection
                            .opacity(contentAppeared ? 1 : 0)
                            .offset(y: contentAppeared ? 0 : 20)

                        // Error message
                        if let error = authService.error {
                            errorView(error)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }

                        Spacer()
                            .frame(height: Spacing.xxl)
                    }
                    .padding(.horizontal, Spacing.lg)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            if authService.isLoading {
                loadingOverlay
            }
        }
        .onAppear {
            // Staggered entrance animations
            withAnimation(.easeOut(duration: 0.6)) {
                logoAppeared = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                contentAppeared = true
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient.subtleBackground
            .ignoresSafeArea()
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        VStack(spacing: Spacing.lg) {
            // App logo - Running figure with heartbeat
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.brandPrimary.opacity(0.25), .clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                // Logo container
                ZStack {
                    // Running figure
                    Image(systemName: "figure.run")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(Color.brandPrimary)

                    // Small heart badge
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.brandAccent)
                        .offset(x: 28, y: -24)
                        .symbolEffect(.pulse, options: .repeating.speed(0.8))
                }
            }

            VStack(spacing: Spacing.sm) {
                Text("viberunner")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text("HR-gated Claude Code tools")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Auth Section

    private var authSection: some View {
        VStack(spacing: Spacing.lg) {
            // GitHub Sign In (primary)
            Button {
                Task {
                    logger.info("GitHub sign in button tapped")
                    do {
                        try await authService.signInWithGitHub()
                    } catch {
                        logger.error("GitHub sign in error: \(error.localizedDescription)")
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    GitHubLogo()
                        .frame(width: 20, height: 20)
                    Text("Continue with GitHub")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(uiColor: .label))
                .foregroundStyle(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)

            // Divider
            dividerView

            // Email/Password form
            emailPasswordForm
        }
    }

    // MARK: - Divider

    private var dividerView: some View {
        HStack(spacing: Spacing.md) {
            Rectangle()
                .fill(.secondary.opacity(0.2))
                .frame(height: 1)

            Text("or")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Rectangle()
                .fill(.secondary.opacity(0.2))
                .frame(height: 1)
        }
    }

    // MARK: - Email/Password Form

    private var emailPasswordForm: some View {
        VStack(spacing: Spacing.md) {
            // Email field
            TextField("Email", text: $email)
                .textFieldStyle(ModernTextFieldStyle())
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)

            // Password field
            SecureField("Password", text: $password)
                .textFieldStyle(ModernTextFieldStyle())
                .textContentType(isSignUp ? .newPassword : .password)

            // Submit button
            Button {
                Task {
                    if isSignUp {
                        try? await authService.signUp(email: email, password: password)
                    } else {
                        try? await authService.signIn(email: email, password: password)
                    }
                }
            } label: {
                Text(isSignUp ? "Sign Up" : "Sign In")
            }
            .buttonStyle(.primary(color: Color.brandPrimary))
            .disabled(email.isEmpty || password.isEmpty)
            .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1)

            // Toggle sign up/in
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSignUp.toggle()
                }
            } label: {
                Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusError)

            Text(message)
                .font(.caption)
                .foregroundStyle(Color.statusError)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.statusError.opacity(0.1))
        )
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: Spacing.md) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)

                Text("Signing in...")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(Spacing.xl)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.lg))
        }
        .transition(.opacity)
    }
}

// MARK: - Modern TextField Style

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - GitHub Logo

struct GitHubLogo: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            Path { path in
                // GitHub Octocat mark - simplified SVG path
                let scale = size / 24.0

                path.move(to: CGPoint(x: 12 * scale, y: 0))
                path.addCurve(
                    to: CGPoint(x: 0, y: 12 * scale),
                    control1: CGPoint(x: 5.37 * scale, y: 0),
                    control2: CGPoint(x: 0, y: 5.37 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 9.29 * scale, y: 23.65 * scale),
                    control1: CGPoint(x: 0, y: 17.31 * scale),
                    control2: CGPoint(x: 3.87 * scale, y: 21.88 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 9.12 * scale, y: 21.35 * scale),
                    control1: CGPoint(x: 10.19 * scale, y: 23.82 * scale),
                    control2: CGPoint(x: 9.12 * scale, y: 22.53 * scale)
                )
                path.addLine(to: CGPoint(x: 9.12 * scale, y: 19.04 * scale))
                path.addCurve(
                    to: CGPoint(x: 4.93 * scale, y: 19.74 * scale),
                    control1: CGPoint(x: 5.7 * scale, y: 19.97 * scale),
                    control2: CGPoint(x: 5.17 * scale, y: 19.97 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 3.62 * scale, y: 17.13 * scale),
                    control1: CGPoint(x: 4.25 * scale, y: 19.04 * scale),
                    control2: CGPoint(x: 3.85 * scale, y: 18.06 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 1.41 * scale, y: 15.35 * scale),
                    control1: CGPoint(x: 3.16 * scale, y: 16.2 * scale),
                    control2: CGPoint(x: 2.33 * scale, y: 15.59 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 2.1 * scale, y: 14.88 * scale),
                    control1: CGPoint(x: 0.97 * scale, y: 15.12 * scale),
                    control2: CGPoint(x: 1.87 * scale, y: 14.88 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 4.7 * scale, y: 16.9 * scale),
                    control1: CGPoint(x: 3.5 * scale, y: 14.88 * scale),
                    control2: CGPoint(x: 4.47 * scale, y: 15.82 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 8.66 * scale, y: 18.45 * scale),
                    control1: CGPoint(x: 5.4 * scale, y: 18.52 * scale),
                    control2: CGPoint(x: 7.48 * scale, y: 18.69 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 9.12 * scale, y: 16.67 * scale),
                    control1: CGPoint(x: 8.66 * scale, y: 17.37 * scale),
                    control2: CGPoint(x: 8.89 * scale, y: 16.9 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 5.4 * scale, y: 11.53 * scale),
                    control1: CGPoint(x: 5.63 * scale, y: 16.2 * scale),
                    control2: CGPoint(x: 3.26 * scale, y: 14.18 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 7.08 * scale, y: 6.86 * scale),
                    control1: CGPoint(x: 6.54 * scale, y: 10.22 * scale),
                    control2: CGPoint(x: 6.31 * scale, y: 7.79 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 7.31 * scale, y: 2.42 * scale),
                    control1: CGPoint(x: 6.77 * scale, y: 5.31 * scale),
                    control2: CGPoint(x: 6.77 * scale, y: 3.58 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 10.34 * scale, y: 4.2 * scale),
                    control1: CGPoint(x: 8.68 * scale, y: 2.65 * scale),
                    control2: CGPoint(x: 10.11 * scale, y: 3.51 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 13.66 * scale, y: 4.2 * scale),
                    control1: CGPoint(x: 11.01 * scale, y: 3.97 * scale),
                    control2: CGPoint(x: 12.99 * scale, y: 3.97 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 16.69 * scale, y: 2.42 * scale),
                    control1: CGPoint(x: 13.89 * scale, y: 3.51 * scale),
                    control2: CGPoint(x: 15.32 * scale, y: 2.65 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 16.92 * scale, y: 6.86 * scale),
                    control1: CGPoint(x: 17.23 * scale, y: 3.58 * scale),
                    control2: CGPoint(x: 17.23 * scale, y: 5.31 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 18.6 * scale, y: 11.53 * scale),
                    control1: CGPoint(x: 17.69 * scale, y: 7.79 * scale),
                    control2: CGPoint(x: 17.46 * scale, y: 10.22 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 14.88 * scale, y: 16.67 * scale),
                    control1: CGPoint(x: 20.74 * scale, y: 14.18 * scale),
                    control2: CGPoint(x: 18.37 * scale, y: 16.2 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 14.88 * scale, y: 19.04 * scale),
                    control1: CGPoint(x: 15.12 * scale, y: 17.14 * scale),
                    control2: CGPoint(x: 14.88 * scale, y: 17.84 * scale)
                )
                path.addLine(to: CGPoint(x: 14.88 * scale, y: 21.35 * scale))
                path.addCurve(
                    to: CGPoint(x: 14.71 * scale, y: 23.65 * scale),
                    control1: CGPoint(x: 14.88 * scale, y: 22.53 * scale),
                    control2: CGPoint(x: 13.81 * scale, y: 23.82 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 24 * scale, y: 12 * scale),
                    control1: CGPoint(x: 20.13 * scale, y: 21.88 * scale),
                    control2: CGPoint(x: 24 * scale, y: 17.31 * scale)
                )
                path.addCurve(
                    to: CGPoint(x: 12 * scale, y: 0),
                    control1: CGPoint(x: 24 * scale, y: 5.37 * scale),
                    control2: CGPoint(x: 18.63 * scale, y: 0)
                )
                path.closeSubpath()
            }
            .fill(Color(uiColor: .systemBackground))
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
}
