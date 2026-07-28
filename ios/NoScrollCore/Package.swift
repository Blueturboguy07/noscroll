// swift-tools-version: 5.9
import PackageDescription

// The platform-independent half of the iOS app: schedule maths and rule-bundle
// canonicalisation. Split out so it can be unit-tested on the host without a
// simulator, an entitlement, or waiting until 3am to see if Sleep Mode releases.
let package = Package(
    name: "NoScrollCore",
    products: [.library(name: "NoScrollCore", targets: ["NoScrollCore"])],
    targets: [
        .target(name: "NoScrollCore"),
        .testTarget(name: "NoScrollCoreTests", dependencies: ["NoScrollCore"]),
    ]
)
