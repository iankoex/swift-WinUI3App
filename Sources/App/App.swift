import Foundation
import SwiftWinUIApplication
import UWP
import WinAppSDK
import WinUI
import WindowsFoundation

@main
final class App: SwiftApplication {
    override func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        let window = Window()
        window.title = "Swift WinUI 3 Demo"

        let root = StackPanel()
        root.spacing = 12
        root.horizontalAlignment = .center
        root.verticalAlignment = .center
        root.margin = Thickness(left: 24, top: 24, right: 24, bottom: 24)

        // --- App logo ---
        let logo = Image()
        logo.width = 128
        logo.height = 128
        logo.horizontalAlignment = .center
        if let pngUrl = Bundle.module.url(forResource: "Picture1", withExtension: "png", subdirectory: "Content") {
            logo.source = BitmapImage(WindowsFoundation.Uri(pngUrl.absoluteString))
        }
        root.children.append(logo)

        // --- Hello World with globe icon ---
        let helloStack = StackPanel()
        helloStack.orientation = .horizontal
        helloStack.spacing = 8
        helloStack.horizontalAlignment = .center

        let hello = TextBlock()
        hello.text = "Hello World"
        hello.fontSize = 32
        hello.verticalAlignment = .center
        helloStack.children.append(hello)

        let globe = FontIcon()
        globe.glyph = "\u{E909}"
        globe.fontSize = 32
        helloStack.children.append(globe)

        root.children.append(helloStack)

        window.content = root
        try! window.activate()

        if let iconUrl = Bundle.module.url(forResource: "app", withExtension: "ico") {
            try? window.appWindow.setTaskbarIcon(iconUrl.path)
            try? window.appWindow.setIcon(iconUrl.path)
        }
    }
}
