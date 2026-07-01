// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "AtlasCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "AtlasCore", targets: ["AtlasCore"])],
    targets: [.target(name: "AtlasCore")]
)
