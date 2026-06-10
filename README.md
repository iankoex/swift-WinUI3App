# Swift WinUI 3 Demo

A Swift-on-Windows WinUI 3 desktop app using the Swift/WinRT bindings and projections. This is a **template project** — clone it, edit `Platform/Package.appxmanifest` and `Platform/packages.config` for your app, and build.

## Overview

Building a WinUI 3 app from Swift requires several layers:

```
Swift source → Swift/WinRT bindings → WinRT metadata (.winmd) → NuGet packages
                                                              → Windows App Runtime
```

The setup pipeline handles this automatically. Package restore uses `nuget`; icon generation, manifest updates, and MSIX packaging use the [winapp CLI](https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/usage):

```
setup.ps1
├── Step 1: prerequisites.ps1        - Check for git, cmake, ninja, Swift, nuget, winapp
├── Step 2: install-swiftwinrt.ps1   - Build swiftwinrt.exe (skipped if already present)
├── Step 3: install-packages.ps1     - nuget restore + copy .pri / .dll / update rsp
├── Step 4: generate-icon-resource.ps1 - winapp manifest update-assets + winapp tool rc
└── Step 5: generate-bindings.ps1    - Run swiftwinrt.exe to produce Swift sources
```

All scripts are idempotent — re-run them safely.

---

## Template placeholders

Before shipping your app, update these in `Platform/Package.appxmanifest`:

| Field | What to set | Notes |
|---|---|---|
| `Identity.Name` | e.g. `Contoso.MyApp` | Reverse-DNS, used as the MSIX package name |
| `Identity.Publisher` | e.g. `CN=Contoso` | **Must match the signing certificate's CN** |
| `Identity.Version` | e.g. `1.0.0.0` | Bump on every Store / sideload submission |
| `Properties.DisplayName` | your app's display name | Shown in the Start menu |
| `Properties.PublisherDisplayName` | your publisher name | Shown in the Apps list |

The `AppIcon.png` source at `Platform/AppIcon.png` is your single source image — drop any square PNG there and `winapp manifest update-assets` will generate the full MSIX asset set.

---

## Quick start

```powershell
# 1. Open a Developer PowerShell for Visual Studio (only required for first-time
#    swiftwinrt.exe build; subsequent runs don't need it)

# 2. Run the full setup (uses pinned versions from packages.config)
.\scripts\setup.ps1

#    ...or fetch the latest NuGet packages instead of the pinned versions
# .\scripts\setup.ps1 -Latest

# 3. Build and run unpackaged
swift run App -c debug

# 4. Build a signed, self-contained MSIX
.\scripts\package.ps1
```

To install just the Swift/WinRT bindings generator separately:

```powershell
.\scripts\install-swiftwinrt.ps1
```

---

## Step-by-step walkthrough

### Step 1: Prerequisites (`prerequisites.ps1`)

The script checks for these tools and offers to install missing ones via winget:

| Tool | Why it's needed |
|------|----------------|
| **winget** | Windows package manager used to install everything else |
| **git** | Clones the swift-winrt source repository |
| **CMake** | Build system used to compile the swift-winrt bindings generator |
| **Ninja** | Fast build generator used by CMake |
| **nuget** | Restores SDK packages from `packages.config` |
| **winapp** | Generates icon assets, runs resource compiler, packs MSIX |
| **Swift** | Compiles the final app — installed via winget (`Swift.Toolchain`) or from [swift.org](https://swift.org/download/) |
| **MSVC (cl.exe)** | **Only required if building swift-winrt from source.** Loaded automatically by `install-swiftwinrt.ps1`; if missing, the script offers winget install of **Visual Studio Build Tools**, then prompts you to add the *MSVC build tools for x64/x86* and *Windows 11 SDK (10.0.26100.0)* components via the Individual Components tab. |
| **Windows SDK** | C++ headers needed to compile swift-winrt; installed as a component of Visual Studio Build Tools (version **10.0.26100** required — no other version works). |

### Step 2: Swift/WinRT bindings generator (`install-swiftwinrt.ps1`)

Fast path: if `.swift-winrt/bin/swiftwinrt.exe` already exists, the script prints "already installed" and exits immediately — **no developer environment loaded**.

Otherwise, it loads the Visual Studio developer environment (using `vswhere` + `Enter-VsDevShell`), then:

- Clones the [thebrowsercompany/swift-winrt](https://github.com/thebrowsercompany/swift-winrt) repo
- Initializes submodules
- Patches `CMakeLists.txt` for MSVC 19.51+ (`/await` → `/await:strict`)
- Builds `swiftwinrt.exe` via `cmake --preset release`
- Copies the binary to `.swift-winrt/bin/`

### Step 3: Restore SDK packages + stage resources (`install-packages.ps1`)

`install-packages.ps1` reads `Platform/packages.config` (standard NuGet XML) and restores the listed packages into the global NuGet cache via `nuget install`:

1. **Restore packages** — by default it runs `nuget install` per package with the pinned versions from `Platform/packages.config`. Pass `-Latest` to ignore the pinned versions and fetch the latest stable versions instead.
2. **Copy `Microsoft.WindowsAppRuntime.Bootstrap.dll`** from the NuGet package cache to `generated/Resources/`
3. **Copy `Microsoft.UI.Xaml.Controls.pri`** from the WinUI NuGet package's `runtimes/win-<arch>/native/` to `generated/Resources/`
4. **Update `generated/swiftwinrt.rsp`** with `-input` lines pointing to the downloaded `.winmd` files
5. **Write `generated/Sources/SwiftWinUIApplication/WindowsAppRuntimeVersion.swift`** with a `WINDOWSAPPSDK_RELEASE_MAJORMINOR` constant derived from the bootstrap DLL's file version

The `Platform/packages.config` package list (used when running without `-Latest`):

| Package | Purpose |
|---|---|
| `Microsoft.WindowsAppSDK` | Metapackage (Foundation + WinUI + Runtime + more) |
| `Microsoft.WindowsAppSDK.Foundation` | WinRT metadata for Windows App SDK foundation |
| `Microsoft.WindowsAppSDK.WinUI` | WinRT metadata for `Microsoft.UI.Xaml.*` |
| `Microsoft.Web.WebView2` | WebView2 control + `Microsoft.Web.WebView2.Core.winmd` |
| `Microsoft.Windows.SDK.Contracts` | Broad WinRT metadata for `Windows.*` namespaces |
| `Microsoft.WindowsAppSDK.InteractiveExperiences` | WinRT metadata for tiles / notifications |
| `Microsoft.WindowsAppSDK.Runtime` | Self-contained MSIX deployment |

### Step 4: Generate icon assets + AppIcon.res (`generate-icon-resource.ps1`)

1. **`winapp manifest update-assets Platform/AppIcon.png --manifest Platform/Package.appxmanifest`** — generates the full MSIX icon set from your single source PNG and **rewrites the manifest in place** to reference them:
   - 5 scale variants (`.scale-100` / `125` / `150` / `200` / `400`)
   - 14 plated targetsize variants
   - 14 unplated targetsize variants
   - `AppIcon.ico` (multi-resolution ICO for shell integration)

   All output goes to `Platform/Assets/`.

2. **`winapp tool rc /nologo _AppIcon.rc`** — compiles `Platform/Assets/AppIcon.ico` to `Platform/Assets/AppIcon.res` (compiled resource linked into the `.exe` via `Package.swift`'s `linkerSettings`).

   The intermediate `_AppIcon.rc` is written by PowerShell and deleted after compilation.

`winapp tool rc` invokes the resource compiler from `Microsoft.Windows.SDK.BuildTools` — **no Visual Studio developer environment needed** at this step.

### Step 5: Generate Swift/WinRT bindings (`generate-bindings.ps1`)

`swiftwinrt.exe` reads the `.winmd` metadata files and generates Swift source code:

```
swiftwinrt.exe @generated/swiftwinrt.rsp
```

Output lands in `generated/Sources/` as several Swift packages:

| Package | Generated from |
|---------|----------------|
| `CWinRT` | Built-in (low-level COM/WinRT interop) |
| `WindowsFoundation` | `Windows.Foundation.*` metadata |
| `WinUI` | `Microsoft.UI.Xaml.*` metadata |
| `UWP` | `Windows.UI.*` metadata |
| `WinAppSDK` | `Microsoft.WindowsAppSDK.*` metadata |
| `WebView2Core` | `Microsoft.Web.WebView2.Core` metadata |
| `SwiftWinUIApplication` | Template (app lifecycle wrapper) |

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
│   ├── Resources/
│   │   ├── Microsoft.UI.Xaml.Controls.pri
│   │   └── Microsoft.WindowsAppRuntime.Bootstrap.dll
│   └── Sources/                       # Generated Swift projections
│       ├── CWinRT/
│       ├── WindowsFoundation/
│       ├── WinUI/
│       ├── UWP/
│       ├── WinAppSDK/
│       ├── WebView2Core/
│       └── SwiftWinUIApplication/
├── Platform/                          # Windows app packaging + assets
│   ├── packages.config                # NuGet package list (used by install-packages.ps1)
│   ├── winapp.yaml                    # winapp CLI config (optional; for winapp restore)
│   ├── Package.appxmanifest           # MSIX manifest (rewritten by winapp on each setup)
│   ├── AppIcon.png                    # Source icon (single PNG)
│   ├── WindowsPackage.pfx             # Auto-generated dev signing cert
│   ├── Content/                       # App resources (Picture1.png, etc.)
│   └── Assets/                        # Generated by winapp manifest update-assets
│       ├── StoreLogo.png              (50x50)
│       ├── AppList.png                (44x44)
│       ├── MedTile.png                (150x150)
│       ├── WideTile.png               (310x150)
│       ├── AppIcon.ico                (multi-size ICO)
│       ├── AppIcon.res                (compiled via winapp tool rc)
│       └── ... (scale + targetsize variants)
├── .swift-winrt/
│   ├── bin/swiftwinrt.exe             # Compiled bindings generator
│   └── source/                        # (optional) swift-winrt source
├── .winapp/                           # Managed by winapp (gitignored)
│   ├── bin/<arch>/                    # Runtime DLLs (Bootstrap, WebView2Loader, etc.)
│   ├── include/                       # C++/WinRT headers
│   └── lib/                           # Static libraries
├── scripts/
│   ├── setup.ps1                      # Full pipeline orchestrator
│   ├── prerequisites.ps1              # Toolchain checks
│   ├── install-swiftwinrt.ps1         # Build swiftwinrt.exe from source
│   ├── install-packages.ps1           # nuget restore + copy .pri / .dll / update rsp
│   ├── generate-icon-resource.ps1     # winapp manifest update-assets + winapp tool rc
│   ├── generate-bindings.ps1          # Generate the Swift bindings
│   └── package.ps1                    # Build a signed self-contained MSIX
├── Package.swift                      # Root Swift package
└── README.md
```
