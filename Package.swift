// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PromptBox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PromptBox", targets: ["PromptBox"])
    ],
    targets: [
        .executableTarget(
            name: "PromptBox",
            path: "Sources/PromptBox",
            exclude: ["Resources"]
        )
    ]
)
