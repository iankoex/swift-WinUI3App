// swift-tools-version:6.0

import Foundation
import PackageDescription

let package = Package(
    name: "generated",
    products: [
        .library(name: "CWinRT", type: .static, targets: ["CWinRT"]),
        .library(name: "WindowsFoundation", type: .static, targets: ["WindowsFoundation"]),
        .library(name: "UWP", type: .static, targets: ["UWP"]),
        .library(name: "WinAppSDK", type: .static, targets: ["WinAppSDK"]),
        .library(name: "WinUI", type: .static, targets: ["WinUI"]),
        .library(name: "SwiftWinUIApplication", type: .static, targets: ["SwiftWinUIApplication"]),
        .library(name: "WebView2Core", type: .static, targets: ["WebView2Core"]),

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
