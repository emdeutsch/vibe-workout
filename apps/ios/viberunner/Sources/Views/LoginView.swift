import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.viberunner.app", category: "LoginView")

struct LoginView: View {
    @EnvironmentObject var authService: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Logo/Title
                VStack(spacing: 8) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.red)

                    Text("viberunner")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("HR-gated Claude Code tools")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                Spacer()

                // Auth buttons
                VStack(spacing: 16) {
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
                        HStack {
                            Image(systemName: "link")
                            Text("Sign in with GitHub")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(.secondary.opacity(0.3))
                            .frame(height: 1)

                        Text("or")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Rectangle()
                            .fill(.secondary.opacity(0.3))
                            .frame(height: 1)
                    }

                    // Email/Password
                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(isSignUp ? .newPassword : .password)

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
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(email.isEmpty || password.isEmpty)

                        Button {
                            isSignUp.toggle()
                        } label: {
                            Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal)

                // Error message
                if let error = authService.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }

                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
            .overlay {
                if authService.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
}
