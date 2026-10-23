// swift-tools-version: 6.0
import PackageDescription
import Foundation

// CLT-only test runs isolate the libraries because this SDK's Testing/Foundation
// overlay is incomplete. Normal builds and Xcode always include the native app.
let testsOnly = ProcessInfo.processInfo.environment["STUDYPILOT_TESTS_ONLY"] == "1"
var products: [Product] = [
    .library(name: "StudyPilotCore", targets: ["StudyPilotCore"]),
    .library(name: "StudyPilotData", targets: ["StudyPilotData"])
]
var targets: [Target] = [
    .target(name: "StudyPilotCore"),
    .target(name: "StudyPilotData", dependencies: ["StudyPilotCore"]),
    .testTarget(name: "StudyPilotCoreTests", dependencies: ["StudyPilotCore"]),
    .testTarget(name: "StudyPilotDataTests", dependencies: ["StudyPilotData", "StudyPilotCore"])
]
if !testsOnly {
    products.append(.executable(name: "StudyPilot", targets: ["StudyPilot"]))
    targets.append(.executableTarget(name: "StudyPilot", dependencies: ["StudyPilotCore", "StudyPilotData", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]))
}
let package = Package(name: "StudyPilot", platforms: [.macOS(.v14)], products: products, dependencies: testsOnly ? [] : [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0")], targets: targets)
