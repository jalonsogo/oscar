// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OScar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OScar",
            path: "Sources/OScar",
            exclude: [
                // Info.plist is copied into the .app bundle by `make bundle` — not a SPM resource
                "Resources/Info.plist"
            ],
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        )
    ]
)
