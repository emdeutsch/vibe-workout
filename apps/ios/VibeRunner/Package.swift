// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeRunner",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "VibeRunner",
            targets: ["VibeRunner"]
        ),
    ],
    dependencies: [
        // Supabase Swift SDK
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "VibeRunner",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            path: "Sources"
        ),
    ]
)
