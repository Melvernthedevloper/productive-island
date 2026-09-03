// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProductiveIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ProductiveIsland", path: "Sources/ProductiveIsland")
    ]
)
