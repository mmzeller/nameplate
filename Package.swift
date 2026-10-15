// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nameplate",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Nameplate", targets: ["Nameplate"]),
        .executable(name: "NameplateCLI", targets: ["NameplateCLI"]),
    ],
    targets: [
        // Gathers the system information. Shared by the app and the command-line tool.
        .target(name: "NameplateCore", path: "Sources/NameplateCore"),
        // The menu bar / desktop app.
        .executableTarget(name: "Nameplate", dependencies: ["NameplateCore"], path: "Sources/Nameplate"),
        // The `nameplate` command-line tool.
        .executableTarget(name: "NameplateCLI", dependencies: ["NameplateCore"], path: "Sources/NameplateCLI"),
    ]
)
