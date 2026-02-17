// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "BlokusApp",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
  ],
  products: [
    .library(name: "Domain", targets: ["Domain"]),
    .library(name: "Engine", targets: ["Engine"]),
    .library(name: "Persistence", targets: ["Persistence"]),
    .library(name: "Connector", targets: ["Connector"]),
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
    .library(name: "Features", targets: ["Features"]),
  ],
  targets: [
    .target(name: "Domain", path: "Sources/Domain"),
    .target(
      name: "Engine",
      dependencies: ["Domain"],
    ),
    .target(
      name: "Persistence",
      dependencies: ["Domain", "Engine"],
    ),
    .target(
      name: "Connector",
      dependencies: ["Engine", "Persistence"],
    ),
    .target(
      name: "DesignSystem",
      dependencies: ["Domain"],
    ),
    .target(
      name: "Features",
      dependencies: ["DesignSystem", "Engine", "Persistence", "Domain"],
    ),
    .testTarget(
      name: "BlokusAppTests",
      dependencies: ["Domain", "Engine", "Persistence", "Connector", "DesignSystem", "Features"]
    ),
  ]
)
