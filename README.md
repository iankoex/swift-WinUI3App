# Swift WinUI 3 Demo [WiP]

A Swift-on-Windows WinUI 3 desktop app using the Swift/WinRT bindings and projections.

## Prerequisites

- **Swift 6.3.0+** — [Download](https://www.swift.org/download/)
- **Windows App Runtime**
- **Windows SDK**
- **SwiftWinRT** — we will build from source which means you need cmake, git, and Visual Studio (compiler tools)

## Quick Start

```powershell
# One-time setup (downloads NuGet packages + WinUI resources)
.\scripts\setup.ps1

# Build & Run
swift run App -c debug
```

## Project Structure

```
├── Sources/App/App.swift                    @main entry point
├── generated/
│   ├── Sources/                             Auto-generated WinRT bindings
│   │   ├── CWinRT/                          C interop layer
│   │   ├── WindowsFoundation/               Windows.Foundation.* types
│   │   ├── UWP/                             Windows.* platform contracts
│   │   ├── WinAppSDK/                       Microsoft.Windows.* types
│   │   ├── WinUI/                           Microsoft.UI.Xaml.* types
│   │   ├── WebView2Core/                    WebView2 bindings
│   │   └── SwiftWinUIApplication/           Bootstrap + Application wrapper
│   ├── Package.swift                        SPM package for generated code
│   ├── Resources/                           WinUI DLLs + PRI files
│   └── swiftwinrt.rsp                       Generator configuration
├── scripts/
│   ├── install-packages.ps1                 Download NuGet packages + WinUI resources
│   ├── generate-bindings.ps1                Regenerate WinRT bindings
│   ├── install-swiftwinrt.ps1               Build swiftwinrt code generator from source
│   └── setup.ps1                            Full one-time setup
├── Package.swift                            Root SPM package
└── README.md
```

## Scripts Reference

| Script | Purpose | When to run |
|---|---|---|
| `scripts\setup.ps1` | Full one-time setup (installs everything) | First clone |
| `scripts\install-packages.ps1` | Downloads NuGet packages + WinUI DLLs/PRI | After fresh clone, or to update packages |
| `scripts\install-swiftwinrt.ps1` | Builds swiftwinrt.exe from source | Only if you need to regenerate bindings with custom types |
| `scripts\generate-bindings.ps1` | Regenerates Swift/WinRT bindings | After updating `swiftwinrt.rsp` with new includes |

## Regenerating Bindings

Edit `generated/swiftwinrt.rsp` to add or remove WinRT namespaces, then:

```powershell
.\scripts\generate-bindings.ps1
```

This runs the swiftwinrt generator with the updated rsp file.
