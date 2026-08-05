import Cocoa
import IOKit.hid

/// Active CGEvent tap that fires on Option+Space and consumes the event so the
/// focused app never sees it (Opt+Space would otherwise type a non-breaking
/// space). Requires Input Monitoring + Accessibility.
final class GlobalHotkeyMonitor: HotkeyMonitor {
    var onActivation: (() -> Void)?

    private static let keyCodeSpace: Int64 = 49
    private static let keyCodeEscape: Int64 = 53

    /// Fired when Esc is pressed while `escapeActive()` returns true (the Esc
    /// press is consumed in that case — used to cancel a recording).
    var onCancel: (() -> Void)?
    var escapeActive: (() -> Bool) = { false }

    /// The chord that triggers activation. Takes effect immediately.
    var keyChord: KeyChord = .optionSpace
    /// Set while the Settings shortcut recorder is capturing, so pressing the
    /// current hotkey there doesn't start a recording.
    var suspended = false
    /// Push-to-talk: key down fires onActivation, key up fires onDeactivation.
    var pushToTalk = false
    var onDeactivation: (() -> Void)?
    private var pttKeyHeld = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var requiredFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if keyChord.command { flags.insert(.maskCommand) }
        if keyChord.option { flags.insert(.maskAlternate) }
        if keyChord.control { flags.insert(.maskControl) }
        if keyChord.shift { flags.insert(.maskShift) }
        return flags
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        // Check only; prompting is the onboarding's job (requestAccess()).
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        DebugLog.log("IOHIDCheckAccess(listen) = \(access.rawValue) (0=granted 1=denied 2=unknown)")
        if access != kIOHIDAccessTypeGranted {
            return false
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
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
        DebugLog.log("event tap created OK (\(keyChord.display))")

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Registers the app in the Input Monitoring pane and triggers the system
    /// prompt. Called from the onboarding Allow button. Actually attempting a
    /// tap is what reliably adds the app to the pane's list, so we try one
    /// (and discard it) besides the IOHID request.
    func requestAccess() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let probe = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        if let probe {
            CGEvent.tapEnable(tap: probe, enable: false)
        }
        DebugLog.log("input monitoring probe tap: \(probe == nil ? "denied (registered in pane)" : "created")")
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

        let modifiers = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])

        if type == .keyDown,
           event.getIntegerValueField(.keyboardEventKeycode) == Self.keyCodeEscape,
           modifiers.isEmpty,
           escapeActive() {
            DispatchQueue.main.async { [weak self] in
                self?.onCancel?()
            }
            return true
        }

        guard !suspended else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Push-to-talk release: match by key code alone, since modifiers may
        // already be up by the time the main key is released.
        if type == .keyUp {
            guard pushToTalk, pttKeyHeld, keyCode == Int64(keyChord.keyCode) else { return false }
            pttKeyHeld = false
            DispatchQueue.main.async { [weak self] in
                self?.onDeactivation?()
            }
            return true
        }

        guard type == .keyDown,
              keyCode == Int64(keyChord.keyCode),
              modifiers == requiredFlags
        else { return false }

        // Ignore key-repeat while the key is held.
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }

        if pushToTalk {
            guard !pttKeyHeld else { return true }
            pttKeyHeld = true
        }
        DispatchQueue.main.async { [weak self] in
            self?.onActivation?()
        }
        return true
    }
}
