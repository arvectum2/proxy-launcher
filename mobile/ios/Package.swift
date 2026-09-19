// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArvectumProxyLauncherIOSCore",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [.library(name: "ArvectumProxyLauncherIOSCore", targets: ["ArvectumProxyLauncherIOSCore"])],
    targets: [
        .target(name: "ArvectumProxyLauncherIOSCore", path: "SharedCore"),
        .testTarget(
            name: "ArvectumProxyLauncherIOSCoreTests",
            dependencies: ["ArvectumProxyLauncherIOSCore"],
            path: "Tests/CoreTests"
        ),
    ]
)
