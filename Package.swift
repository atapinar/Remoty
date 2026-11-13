// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AndroidTVMenubar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AndroidTVMenubar", targets: ["AndroidTVMenubar"])],
    targets: [.executableTarget(name: "AndroidTVMenubar", resources: [.copy("AppIcons"), .copy("AppAssets"), .copy("Helpers")])]
)
