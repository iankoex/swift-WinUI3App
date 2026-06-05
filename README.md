# Swift WinUI 3 Demo

A Swift-on-Windows WinUI 3 desktop app using the Swift/WinRT bindings and projections.

## Overview

Building a WinUI 3 app from Swift requires several layers:

```
Swift source → Swift/WinRT bindings → WinRT metadata (.winmd) → NuGet packages
                                                              → Windows App Runtime
```

The setup pipeline handles this automatically:

```
setup.ps1
├── Step 1: prerequisites.ps1        - Check for git, cmake, ninja, Swift, MSVC
├── Step 2: install-packages.ps1     - Download NuGet packages + system runtime
└── Step 3: generate-bindings.ps1    - Run swiftwinrt.exe to produce Swift sources
```

All scripts are idempotent - you can re-run them safely.

---

## Step-by-step walkthrough

### Step 1: Prerequisites (`prerequisites.ps1`)

The script checks for these tools and prompts to install any that are missing via winget:

| Tool | Why it's needed |
|------|----------------|
| **winget** | Windows package manager used to install everything else |
| **git** | Clones the swift-winrt source repository |
| **CMake** | Build system used to compile the swift-winrt binder |
| **Ninja** | Fast build generator used by CMake |
| **Swift** | Compiles the final app - download manually from [swift.org](https://swift.org/download/) |
| **MSVC (cl.exe)** | C++ compiler needed to build swift-winrt and to link the final Swift binary against the Windows SDK |

> You must run from a **Developer PowerShell for VS 2022** so that `cl.exe`, the Windows SDK headers, and linker paths are all available in the environment. The script will attempt to load the dev shell automatically if it detects Visual Studio is installed.

### Step 2: Install NuGet packages (`install-packages.ps1`)

This script downloads everything the binder and the runtime need:

#### 2a. Resolve latest package versions (in parallel)

The script queries `api.nuget.org` for the latest **stable** release of each of the 5 required packages. Each query runs as a separate background job so all 5 versions are resolved concurrently instead of sequentially.

#### 2b. Download packages via nuget.exe

The script generates a `packages.config` with the resolved versions and runs `nuget.exe restore` to download and extract each package. Already-cached packages (where the versioned directory already exists) are skipped.

> `nuget.exe` is downloaded to `%TEMP%` by `prerequisites.ps1` if not already present.

| Package | What it provides |
|---------|-----------------|
| `Microsoft.WindowsAppSDK.Foundation` | Bootstrap DLL + WinRT metadata for the Windows App SDK foundation layer |
| `Microsoft.WindowsAppSDK.WinUI` | WinRT metadata for `Microsoft.UI.Xaml.*` (controls, styling, layout) |
| `Microsoft.Web.WebView2` | WinRT metadata + the WebView2 control winmd |
| `Microsoft.Windows.SDK.Contracts` | Broad WinRT metadata for `Windows.*` namespaces |
| `Microsoft.WindowsAppSDK.InteractiveExperiences` | WinRT metadata for interactive/tile/notification APIs |

#### 2c. Copy runtime DLLs

The bootstrap DLL (`Microsoft.WindowsAppRuntime.Bootstrap.dll`) is copied from the extracted Foundation package into `generated/Resources/`. The WinUI resource file (`Microsoft.UI.Xaml.Controls.pri`) is copied from the WinUI package. These files are needed at app launch.

#### 2d. Resolve system Windows App Runtime

The script queries `Get-AppxPackage` to find the **latest system-installed** Windows App Runtime version. This is the runtime installed via the Microsoft Store or the Windows App SDK installer - not the NuGet packages. It extracts the version from `Microsoft.WindowsAppRuntime.dll` and writes it to `WindowsAppRuntimeVersion.swift`.

The version is resolved from the **package name**, not the `PackageVersion` field, because Microsoft uses inflated build numbers for 1.x packages (1.6 → 6000, 1.8 → 8000) that don't sort correctly against 2.x package versions.

#### 2e. Update `swiftwinrt.rsp`

The response file (`generated/swiftwinrt.rsp`) tells `swiftwinrt.exe` where to find the WinRT metadata. This step replaces the `-input` lines with absolute paths to the downloaded NuGet packages.

### Step 3: Generate Swift/WinRT bindings (`generate-bindings.ps1`)

`swiftwinrt.exe` reads the `.winmd` metadata files and generates Swift source code:

```
swiftwinrt.exe @generated/swiftwinrt.rsp
```

The `@` syntax reads arguments from the response file. The output lands in `generated/Sources/` as several Swift packages:

| Package | Generated from |
|---------|---------------|
| `CWinRT` | Built-in (low-level COM/WinRT interop) |
| `WindowsFoundation` | `Windows.Foundation.*` metadata |
| `WinUI` | `Microsoft.UI.Xaml.*` metadata |
| `UWP` | `Windows.UI.*` metadata |
| `WinAppSDK` | `Microsoft.WindowsAppSDK.*` metadata |
| `SwiftWinUIApplication` | Template (app lifecycle wrapper) |

These are declared as local dependencies in `generated/Package.swift`, which the root `Package.swift` references with `.package(path: "generated")`.

---

## Quick start

```powershell
# 1. Open a Developer PowerShell for VS 2022

# 2. Run the full setup
.\scripts\setup.ps1

# 3. Build and run
swift run App -c debug
```

To install just the Swift/WinRT binder separately:

```powershell
.\scripts\install-swiftwinrt.ps1
```

---

## Project structure

```
swift-WinUI3App/
├── Sources/
│   └── App/
│       └── App.swift                  # Main entry point
├── Tests/
│   └── AppTests/
├── generated/
│   ├── swiftwinrt.rsp                 # Response file for swiftwinrt.exe
│   ├── Package.swift                  # Generated bindings package manifest
│   ├── Resources/                     # Runtime DLLs + PRI files
│   └── Sources/                       # Generated Swift projections
│       ├── CWinRT/
│       ├── WindowsFoundation/
│       ├── WinUI/
│       ├── UWP/
│       ├── WinAppSDK/
│       └── SwiftWinUIApplication/
├── .swift-winrt/
│   ├── bin/swiftwinrt.exe             # Compiled bindings generator
│   └── source/                        # (optional) swift-winrt source
├── .nuget-packages/                   # Cached NuGet downloads
├── scripts/
│   ├── setup.ps1                      # Full pipeline orchestrator
│   ├── prerequisites.ps1              # Toolchain checks
│   ├── install-packages.ps1           # NuGet + runtime setup
│   ├── install-swiftwinrt.ps1         # Build swiftwinrt.exe from source
│   └── generate-bindings.ps1          # Generate the bindings
├── Package.swift                      # Root Swift package
└── README.md
```
