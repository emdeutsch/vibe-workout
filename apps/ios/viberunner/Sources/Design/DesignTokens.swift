import SwiftUI

// MARK: - Spacing Scale

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius Scale

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Semantic Colors

extension Color {
    // Status colors
    static let statusSuccess = Color.green
    static let statusError = Color.red
    static let statusWarning = Color.orange

    // Heart rate specific
    static let hrAboveThreshold = Color.green
    static let hrBelowThreshold = Color.red
    static let hrNeutral = Color.secondary

    // Brand - Orange/Amber scheme
    static let brandPrimary = Color(red: 1.0, green: 0.45, blue: 0.0) // Vibrant orange
    static let brandAccent = Color(red: 1.0, green: 0.6, blue: 0.0)   // Amber/gold
    static let brandDark = Color(red: 0.85, green: 0.35, blue: 0.0)   // Darker orange for contrast
}

// MARK: - Gradients

extension LinearGradient {
    static let brandGradient = LinearGradient(
        colors: [
            Color.brandPrimary.opacity(0.9),
            Color.brandAccent.opacity(0.7)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleBackground = LinearGradient(
        colors: [
            Color.brandPrimary.opacity(0.08),
            Color.clear,
            Color.brandPrimary.opacity(0.03)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
