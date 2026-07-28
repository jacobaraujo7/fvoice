import Cocoa
import IOKit.hid

/// CGEvent tap (listen-only) that fires when the Option+Command chord becomes
/// active. Modifier-only chord, so nothing needs to be consumed and Opt+letter
/// accents keep working. Requires Input Monitoring permission.
final class GlobalHotkeyMonitor: HotkeyMonitor {
    var onActivation: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var comboWasActive = false

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        // Registers the app in the Input Monitoring pane and triggers the
        // system prompt on first run — tapCreate alone fails silently without it.
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            return false
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

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
        comboWasActive = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let flags = event.flags
        let comboActive = flags.contains(.maskAlternate) && flags.contains(.maskCommand)
        defer { comboWasActive = comboActive }

        // Rising edge only: fire once when both modifiers become held together.
        guard comboActive, !comboWasActive else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onActivation?()
        }
    }
}
