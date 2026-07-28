import Foundation

/// Monitors a global hotkey chord and fires on each activation (toggle semantics
/// are handled by the caller — this just reports "the chord was pressed").
protocol HotkeyMonitor: AnyObject {
    var onActivation: (() -> Void)? { get set }
    /// Returns false when the system denied the event tap (missing permission).
    @discardableResult func start() -> Bool
    func stop()
}
