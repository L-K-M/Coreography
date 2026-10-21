// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Coreography",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "CoreographyDrivers", targets: ["CoreographyDrivers"]),
        .library(name: "CoreographyKit", targets: ["CoreographyKit"]),
        .library(name: "CoreographyServices", targets: ["CoreographyServices"]),
        .executable(name: "coreo", targets: ["coreo"]),
        .executable(name: "CoreographyHelper", targets: ["CoreographyHelper"])
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
        .executableTarget(name: "CoreographyHelper", dependencies: ["CoreographyDrivers"]),
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
