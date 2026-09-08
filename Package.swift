// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SampleAtlas",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SampleAtlas", targets: ["SampleAtlas"]),
               .library(name: "AtlasCore", targets: ["AtlasCore"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "AtlasCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "SampleAtlas", dependencies: ["AtlasCore"]),
        .testTarget(name: "AtlasCoreTests", dependencies: ["AtlasCore"])
    ]
)
