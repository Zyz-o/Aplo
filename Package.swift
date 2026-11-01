// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aplo",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Aplo", targets: ["Aplo"])],
    targets: [
        .executableTarget(name: "Aplo", path: "Sources", linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
            .linkedFramework("Carbon"), .linkedLibrary("sqlite3")
        ]),
        .testTarget(name: "AploTests", dependencies: ["Aplo"], path: "Tests", exclude: ["test_installer.py"])
    ]
)
