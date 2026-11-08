// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Neylu",
  platforms: [.macOS(.v12)],
  targets: [
    .systemLibrary(name: "NeyluLegacyServiceManagement", path: "Sources/LegacyServiceManagement"),
    .target(
      name: "NeyluCore", dependencies: ["NeyluLegacyServiceManagement"], path: "Sources",
      exclude: ["main.swift", "Updater", "LoginHelper", "LegacyServiceManagement"],
      linkerSettings: [
        .linkedLibrary("sqlite3"), .linkedFramework("Carbon"),
        .linkedFramework("ServiceManagement"), .linkedFramework("DiskArbitration"),
      ]),
    .testTarget(name: "NeyluTests", dependencies: ["NeyluCore"], path: "Tests/Swift"),
  ],
  swiftLanguageModes: [.v5]
)
