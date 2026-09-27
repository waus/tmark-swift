// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TMarkSwift",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TMark", targets: ["TMark"]),
        .library(name: "TMarkSwiftUI", targets: ["TMarkSwiftUI"]),
    ],
    targets: [
        .target(name: "TMark"),
        .target(name: "TMarkSwiftUI", dependencies: ["TMark"]),
        .testTarget(
            name: "TMarkTests",
            dependencies: ["TMark"],
            resources: [.copy("Resources/Fixtures")]
        ),
        .testTarget(name: "TMarkSwiftUITests", dependencies: ["TMarkSwiftUI"]),
    ]
)
