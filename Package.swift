// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Neylu",
  platforms: [.macOS(.v12)],
  targets: [
    .target(
      name: "NeyluCore", path: "Sources", exclude: ["main.swift", "Updater", "LoginHelper"],
      linkerSettings: [
        .linkedLibrary("sqlite3"), .linkedFramework("Carbon"),
        .linkedFramework("ServiceManagement"), .linkedFramework("DiskArbitration"),
      ]),
    .testTarget(name: "NeyluTests", dependencies: ["NeyluCore"], path: "Tests/Swift"),
  ],
  swiftLanguageModes: [.v5]
)
