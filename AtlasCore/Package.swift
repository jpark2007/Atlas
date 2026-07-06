// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "AtlasCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "AtlasCore", targets: ["AtlasCore"])],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(name: "AtlasCore", dependencies: [
            .product(name: "Realtime", package: "supabase-swift")
        ]),
        .testTarget(name: "AtlasCoreTests", dependencies: ["AtlasCore"]),
    ]
)
