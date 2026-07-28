import Foundation

enum InsertMode: String, Codable, CaseIterable, Identifiable {
    case typing
    case paste
    var id: String { rawValue }
    var label: String {
        switch self {
        case .typing: return "Digitação (recomendado)"
        case .paste: return "Colar (⌘V sintético)"
        }
    }
}

enum HotkeyChord: String, Codable, CaseIterable, Identifiable {
    case optionSpace
    case controlOptionSpace
    case commandShiftSpace
    var id: String { rawValue }
    var label: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .controlOptionSpace: return "⌃⌥ Space"
        case .commandShiftSpace: return "⌘⇧ Space"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var language: String = "pt"          // "auto" = detect (opt-in only)
    var insertMode: InsertMode = .typing
    var autoEnter: Bool = false          // press Return after inserting
    var hotkey: HotkeyChord = .optionSpace
    var launchAtLogin: Bool = false
}
