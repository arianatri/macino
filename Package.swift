// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "macino", platforms: [.macOS(.v14)], products: [.executable(name: "macino", targets: ["macino"])], targets: [.executableTarget(name: "macino"), .executableTarget(name: "macinoInstaller")])
