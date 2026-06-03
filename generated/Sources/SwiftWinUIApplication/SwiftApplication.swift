import CWinRT
import Foundation
import WinAppSDK
@_spi(WinRTInternal) @_spi(WinRTImplements) import WinUI
@_spi(WinRTInternal) @_spi(WinRTImplements) import WindowsFoundation

open class SwiftApplication: Application, IXamlMetadataProvider {

    public required override init() {
        super.init()
        resourceManagerRequested.addHandler { _, eventArgs in
            guard let eventArgs = eventArgs else { return }
            let priURL = Bundle.module.url(
                forResource: "Microsoft.UI.Xaml.Controls", withExtension: "pri"
            )
            if let priURL {
                eventArgs.customResourceManager = ResourceManager(priURL.path)
            } else {
                print("No PRI file found")
            }
        }
    }

    override open func onLaunched(_ args: LaunchActivatedEventArgs?) {
        if let args = args {
            resources.mergedDictionaries.append(XamlControlsResources())
            onLaunched(args)
        }
    }

    open func onLaunched(_ args: LaunchActivatedEventArgs) {
    }

    open func onShutdown() {
    }

    public static func main() {
        guard let entryClass = NSClassFromString("App.App") as? SwiftApplication.Type else {
            fatalError(
                """
                Could not find the SwiftApplication entry class "App.App".
                Ensure your @main class is named `App` and lives in the `App` target,
                or override `static func main` to call `SwiftApplication.run(Self.self)` directly.
                """
            )
        }
        run(entryClass)
    }

    public static func run(_ appType: SwiftApplication.Type) {
        do {
            try withExtendedLifetime(WindowsAppRuntimeInitializer()) {
                MainRunLoopTickler.setup()
                defer { MainRunLoopTickler.shutdown() }
                var application: SwiftApplication!
                try Application.start { _ in
                    application = appType.init()
                }
                application?.onShutdown()
            }
        } catch {
            fatalError("\(error)")
        }
    }

    override open func queryInterface(_ iid: WindowsFoundation.IID) -> IUnknownRef? {
        switch iid {
            case __ABI_Microsoft_UI_Xaml_Markup.IXamlMetadataProviderWrapper.IID:
                let wrapper = __ABI_Microsoft_UI_Xaml_Markup.IXamlMetadataProviderWrapper(self)
                return wrapper?.queryInterface(iid)
            default:
                return super.queryInterface(iid)
        }
    }

    private lazy var metadataProvider: XamlControlsXamlMetaDataProvider = .init()

    public func getXamlType(_ type: TypeName) throws -> AnyIXamlType! {
        try metadataProvider.getXamlType(type)
    }

    public func getXamlType(_ fullName: String) throws -> AnyIXamlType! {
        try metadataProvider.getXamlType(fullName)
    }

    public func getXmlnsDefinitions() throws -> [XmlnsDefinition] {
        try metadataProvider.getXmlnsDefinitions()
    }
}
