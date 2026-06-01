// swift-tools-version:6.0

import Foundation
import PackageDescription

let package = Package(
    name: "generated",
    products: [
        .library(name: "CWinRT", targets: ["CWinRT"]),
        .library(name: "WindowsFoundation", targets: ["WindowsFoundation"]),
        .library(name: "UWP", targets: ["UWP"]),
        .library(name: "WinAppSDK", targets: ["WinAppSDK"]),
        .library(name: "WinUI", targets: ["WinUI"]),
        .library(name: "SwiftWinUIApplication", targets: ["SwiftWinUIApplication"]),
        .library(name: "WebView2Core", targets: ["WebView2Core"]),

    ],
    targets: [
        .target(
            name: "CWinRT"
        ),
        .target(
            name: "WindowsFoundation",
            dependencies: [
                "CWinRT"
            ],
        ),
        .target(
            name: "UWP",
            dependencies: [
                "WindowsFoundation"
            ],
        ),
        .target(
            name: "WebView2Core",
            dependencies: [
                "WindowsFoundation",
                "UWP",
            ],
        ),
        .target(
            name: "WinAppSDK",
            dependencies: [
                "WindowsFoundation",
                "UWP",
                "CWinRT",
            ],
        ),
        .target(
            name: "WinUI",
            dependencies: [
                "WindowsFoundation",
                "UWP",
                "WinAppSDK",
                "WebView2Core",
            ],
        ),
        .target(
            name: "SwiftWinUIApplication",
            dependencies: [
                "CWinRT",
                "WindowsFoundation",
                "UWP",
                "WinAppSDK",
                "WinUI",
            ],
            resources: [.copy("../../Resources/")],
        ),
    ],
    swiftLanguageModes: [.v5]
)
