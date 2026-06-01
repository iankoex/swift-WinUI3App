import CWinRT
import Foundation
import WinAppSDK
@_spi(WinRTInternal) @_spi(WinRTImplements) import WinUI
@_spi(WinRTInternal) @_spi(WinRTImplements) import WindowsFoundation

private typealias pfnMddBootstrapInitialize2 =
    @convention(c) (
        UInt32, UnsafePointer<UInt16>?, UInt64, UInt32
    ) -> Int32

private typealias pfnMddBootstrapShutdown = @convention(c) () -> Void

private let APPMODEL_ERROR_NO_PACKAGE: Int32 = 15700
private let MDDBOOTSTRAP_INITIALIZE_OPTIONS_ON_NO_MATCH_SHOW_UI: UInt32 = 0x01

private struct MddBootstrapInitializeOptions: OptionSet {
    let rawValue: UInt32
    static let none: Self = []
    static let onNoMatchShowUI: Self = .init(
        rawValue: MDDBOOTSTRAP_INITIALIZE_OPTIONS_ON_NO_MATCH_SHOW_UI)
}

public enum ThreadingModel {
    case single
    case multi
}

enum InitializationError: LocalizedError {
    case failedToInstallWindowsAppRuntime
    case missingBootstrapper
    case failedToLoadBootstrapper(_ path: String)
    case missingExecutableURL

    var errorDescription: String? {
        switch self {
            case .failedToInstallWindowsAppRuntime:
                return "Failed to install Windows App Runtime (installer produced non-zero exit status)"
            case .missingBootstrapper:
                return "Could not find bootstrapper DLL"
            case .failedToLoadBootstrapper(let path):
                return "Failed to load bootstrapper DLL at \(path)"
            case .missingExecutableURL:
                return "Missing executable URL"
        }
    }
}

/// WindowsAppRuntimeInitializer is used to properly initialize the Windows App SDK runtime, along with the Windows Runtime.
/// The runtime is initialized for the lifetime of the object, and is deinitialized when the object is deallocated.
public class WindowsAppRuntimeInitializer {
    private let bootstrapperDll: HMODULE?

    private lazy var Initialize: pfnMddBootstrapInitialize2 = {
        let pfn = GetProcAddress(bootstrapperDll, "MddBootstrapInitialize2")
        return unsafeBitCast(pfn, to: pfnMddBootstrapInitialize2.self)
    }()

    private lazy var Shutdown: pfnMddBootstrapShutdown = {
        let pfn = GetProcAddress(bootstrapperDll, "MddBootstrapShutdown")
        return unsafeBitCast(pfn, to: pfnMddBootstrapShutdown.self)
    }()

    private func processHasIdentity() -> Bool {
        var length: UInt32 = 0
        return GetCurrentPackageFullName(&length, nil) != APPMODEL_ERROR_NO_PACKAGE
    }

    public init(threadingModel: ThreadingModel = .multi) throws {
        let bundleDllURL = Bundle.module.url(
            forResource: "Microsoft.WindowsAppRuntime.Bootstrap",
            withExtension: "dll"
        )
        let libraryPath: String
        if let bundleDllURL = bundleDllURL {
            libraryPath = bundleDllURL.path
        } else {
            print("Expected to find bootstrapper dll in Bundle.module")
            throw InitializationError.missingBootstrapper
        }
        guard let dll = libraryPath.withCString({ LoadLibraryA($0) }) else {
            print("Failed to load bootstrapper dll at \(libraryPath)")
            throw InitializationError.failedToLoadBootstrapper(libraryPath)
        }
        bootstrapperDll = dll

        let roInitParam: RO_INIT_TYPE =
            switch threadingModel {
                case .single: RO_INIT_TYPE(0)
                case .multi: RO_INIT_TYPE(1)
            }

        let hr = RoInitialize(roInitParam)
        if hr < 0 {
            throw InitializationError.failedToInstallWindowsAppRuntime
        }

        _ = SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE)

        if processHasIdentity() {
            return
        }

        do {
            let result = Initialize(WINDOWSAPPSDK_RELEASE_MAJORMINOR, nil, 0, 0)
            if result < 0 {
                throw InitializationError.failedToInstallWindowsAppRuntime
            }
        } catch {
            print("Windows App Runtime not found on system")
            throw error
        }
    }

    deinit {
        RoUninitialize()
        if !processHasIdentity() {
            Shutdown()
        }
        _ = FreeLibrary(bootstrapperDll)
    }
}
