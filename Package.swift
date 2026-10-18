// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Coreography",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "CoreographyKit", targets: ["CoreographyKit"]),
        .library(name: "CoreographyServices", targets: ["CoreographyServices"]),
        .executable(name: "coreo", targets: ["coreo"])
    ],
    targets: [
        .target(name: "CoreographySystem", linkerSettings: [
            .linkedFramework("IOKit", .when(platforms: [.macOS]))
        ]),
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "CoreographyDrivers", dependencies: [
            .target(name: "CoreographySystem", condition: .when(platforms: [.macOS])),
            "CSQLite"
        ]),
        .target(name: "CoreographyKit", dependencies: ["CoreographyDrivers"]),
        .target(name: "CoreographyServices", dependencies: ["CoreographyKit"]),
        .executableTarget(name: "coreo", dependencies: ["CoreographyServices"]),
        .testTarget(
            name: "CoreographyKitTests",
            dependencies: ["CoreographyKit", "CoreographyDrivers"]
        ),
        .testTarget(
            name: "CoreographyServicesTests",
            dependencies: ["CoreographyServices", "CoreographyKit", "CoreographyDrivers"]
        )
    ]
)
