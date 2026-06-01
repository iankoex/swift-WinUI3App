import Foundation
import SwiftWinUIApplication
import UWP
import WinAppSDK
import WinUI

@main
final class App: SwiftApplication {
    override func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        let window = Window()
        window.title = "Swift WinUI 3 Demo"

        let root = StackPanel()
        root.spacing = 12
        root.margin = Thickness(left: 24, top: 24, right: 24, bottom: 24)

        let title = TextBlock()
        title.text = "Welcome to Swift WinUI 3"
        title.fontSize = 28
        title.fontWeight = FontWeight(weight: 700)
        root.children.append(title)

        let subtitle = TextBlock()
        subtitle.text = "Running on Windows App SDK"
        subtitle.fontSize = 14
        root.children.append(subtitle)

        let infoBar = InfoBar()
        infoBar.title = "Ready"
        infoBar.message = "App initialized successfully"
        infoBar.severity = .success
        infoBar.isOpen = true
        root.children.append(infoBar)

        let button = Button()
        button.content = "Click Me"
        button.click.addHandler { _, _ in
            print("Button clicked!")
        }
        root.children.append(button)

        let slider = Slider()
        slider.header = "Volume"
        slider.minimum = 0
        slider.maximum = 100
        slider.value = 35
        root.children.append(slider)

        let toggle = ToggleSwitch()
        toggle.header = "Switch"
        toggle.isOn = false
        root.children.append(toggle)

        let progress = ProgressBar()
        progress.value = 65
        progress.width = 200
        root.children.append(progress)

        let scroll = ScrollViewer()
        scroll.content = root

        window.content = scroll
        try! window.activate()

        _ = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            // if you can see this in the console
            // then it means that the MainRunLoopTickler is working
            print("Timer fired at \(Date())")
        }
    }
}
