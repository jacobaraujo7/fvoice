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
    /// When true, media Play/Pause (AirPods stem press) also toggles and is
    /// consumed so it stops controlling playback. Takes effect immediately.
    var mediaKeyEnabled = false

    private static let systemDefinedEventType = CGEventType(rawValue: 14)!  // NX_SYSDEFINED
    private static let mediaKeySubtype: Int16 = 8
    private static let keyPlayPause: Int = 16  // NX_KEYTYPE_PLAY

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
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << Self.systemDefinedEventType.rawValue)
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

        if type == Self.systemDefinedEventType {
            return handleMediaKey(event)
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

    /// Returns true (consume) when the event is a Play/Pause press and the
    /// media-key toggle is enabled. Both key-down and key-up are consumed so
    /// the media system never sees half a press.
    private func handleMediaKey(_ event: CGEvent) -> Bool {
        guard mediaKeyEnabled,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.mediaKeySubtype
        else { return false }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        guard keyCode == Self.keyPlayPause else { return false }

        let isKeyDown = ((data & 0xFF00) >> 8) == 0x0A
        if isKeyDown {
            DispatchQueue.main.async { [weak self] in
                self?.onActivation?()
            }
        }
        return true
    }
}
