import Foundation
import CWinRT
@_spi(WinRTInternal) @_spi(WinRTImplements) import WinUI
@_spi(WinRTInternal) @_spi(WinRTImplements) import WindowsFoundation
import WinAppSDK

final class MainRunLoopTickler {
    private var timerID: UINT_PTR = 0

    private var readyToProcessMessages = false
    private var doWorkRecursionGuard = false

    fileprivate static let minIdleDelay: TimeInterval = 0.05
    fileprivate static let maxIdleDelay: TimeInterval = 1
    private static let doWorkMessage = UINT(WM_USER + 0xbc0)

    private var nextIdleDelay: TimeInterval = MainRunLoopTickler.minIdleDelay
    fileprivate static let instance: MainRunLoopTickler = .init()

    static func setup() {
        instance.start()
    }

    static func shutdown() {
        instance.shutdown()
    }

    private var hook: HHOOK?
    private func start() {
        hook = SetWindowsHookExW(
            WH_CALLWNDPROCRET, runLoopTicklerWindowHook, nil, GetCurrentThreadId())
        scheduleImmediateWork()
    }

    fileprivate func scheduleDelayedWork(after delay: TimeInterval) {
        let cappedDelay: TimeInterval
        if delay >= nextIdleDelay {
            cappedDelay = nextIdleDelay
            nextIdleDelay = min(nextIdleDelay + Self.minIdleDelay, Self.maxIdleDelay)
        } else {
            cappedDelay = max(delay, 0)
        }
        let delayMilliseconds = UInt32(cappedDelay * 1000)
        timerID = SetTimer(nil, timerID, delayMilliseconds, runLoopTicklerTimerProc)
    }

    fileprivate func scheduleImmediateWork() {
        MainRunLoopTickler.instance.nextIdleDelay = MainRunLoopTickler.minIdleDelay

        if readyToProcessMessages {
            guard PostMessageW(nil, MainRunLoopTickler.doWorkMessage, 0, 0) else {
                print(
                    "Failed to post message to message window. Win32 Error Code: \(GetLastError())")
                return
            }
        } else {
            scheduleDelayedWork(after: 0)
        }
    }

    fileprivate func shutdown() {
        UnhookWindowsHookEx(hook)
        KillTimer(nil, timerID)
    }

    fileprivate func doWork() {
        guard doWorkRecursionGuard == false else { return }
        doWorkRecursionGuard = true
        defer { doWorkRecursionGuard = false }

        let nextDate = RunLoop.main.limitDate(forMode: .default)
        let nextDelay = nextDate?.timeIntervalSinceNow ?? 0
        scheduleDelayedWork(after: nextDelay)
    }
}

private let runLoopTicklerWindowHook: HOOKPROC = { (nCode: Int32, wParam: WPARAM, lParam: LPARAM) in
    if nCode >= 0 {
        let ptr = UnsafeRawPointer(bitPattern: Int(lParam))?.assumingMemoryBound(
            to: CWPRETSTRUCT.self)
        if let msgInfo = ptr?.pointee {
            if (msgInfo.message >= WM_KEYFIRST && msgInfo.message < WM_KEYLAST)
                || (msgInfo.message >= WM_MOUSEFIRST && msgInfo.message < WM_MOUSELAST)
            {
                MainRunLoopTickler.instance.scheduleImmediateWork()
            } else if msgInfo.message != WM_GETICON {
                MainRunLoopTickler.instance.scheduleDelayedWork(after: 0)
            }
        }
    }
    return CallNextHookEx(nil, nCode, wParam, lParam)
}

private let runLoopTicklerTimerProc: TIMERPROC = { (_: HWND?, _: UINT, _: UINT_PTR, _: DWORD) in
    MainRunLoopTickler.instance.doWork()
}
