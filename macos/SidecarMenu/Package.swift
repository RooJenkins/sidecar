// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SidecarMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SidecarMenu",
            path: "Sources",
            resources: [
                .copy("../PrivacyInfo.xcprivacy"),
                .copy("../Resources/MenuBarIcon.png"),
            ]
        )
    ]
)
