import Cocoa
import IOKit.hid

/// Active CGEvent tap that fires on Option+Space and consumes the event so the
/// focused app never sees it (Opt+Space would otherwise type a non-breaking
/// space). Requires Input Monitoring + Accessibility.
final class GlobalHotkeyMonitor: HotkeyMonitor {
    var onActivation: (() -> Void)?

    private static let keyCodeSpace: Int64 = 49

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        // Registers the app in the Input Monitoring pane and triggers the
        // system prompt on first run — tapCreate alone fails silently without it.
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        DebugLog.log("IOHIDCheckAccess(listen) = \(access.rawValue) (0=granted 1=denied 2=unknown)")
        if access != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            return false
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            if monitor.handle(type: type, event: event) {
                return nil  // consume: the focused app must not receive the key
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DebugLog.log("CGEvent.tapCreate FAILED (active tap needs Accessibility)")
            return false
        }
        DebugLog.log("event tap created OK (Opt+Space)")

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    /// Returns true when the event was the hotkey and must be consumed.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventKeycode) == Self.keyCodeSpace,
              event.flags.contains(.maskAlternate),
              !event.flags.contains(.maskCommand),
              !event.flags.contains(.maskControl)
        else { return false }

        // Ignore key-repeat while Space is held.
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }

        DispatchQueue.main.async { [weak self] in
            self?.onActivation?()
        }
        return true
    }
}
