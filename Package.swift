// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Tox",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .systemLibrary(
            name: "CToxCoreSystem",
            pkgConfig: "toxcore",
            providers: [
                .brew(["toxcore"])
            ]
        ),
        .target(
            name: "CToxWrapper",
            dependencies: ["CToxCoreSystem"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("toxcore")
            ]
        ),
        .executableTarget(
            name: "Tox",
            dependencies: ["CToxWrapper"],
            exclude: [
                "Resources/16.png",
                "Resources/32.png",
                "Resources/64.png",
                "Resources/128.png",
                "Resources/256.png",
                "Resources/512.png",
                "Resources/1024.png",
                "Resources/Contents.json",
                "Resources/AppIcon.appiconset"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
    ]
)
