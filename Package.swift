// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InputOverlay",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "InputOverlay",
            path: ".",
            exclude: ["Info.plist", "build_app.sh", "README.md"],
            sources: [
                "App.swift",
                "AppDelegate.swift",
                "Settings.swift",
                "InputMonitor.swift",
                "KeyLayout.swift",
                "OverlayView.swift",
            ]
        )
    ]
)
