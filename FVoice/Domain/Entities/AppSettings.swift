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
    /// AirPods stem press (media Play/Pause) toggles recording. While on,
    /// the press no longer controls media playback.
    var mediaKeyToggle: Bool = false

    init() {}

    // Tolerant decoding so config.json files from older versions keep working
    // when new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "pt"
        insertMode = try c.decodeIfPresent(InsertMode.self, forKey: .insertMode) ?? .typing
        autoEnter = try c.decodeIfPresent(Bool.self, forKey: .autoEnter) ?? false
        hotkey = try c.decodeIfPresent(HotkeyChord.self, forKey: .hotkey) ?? .optionSpace
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        mediaKeyToggle = try c.decodeIfPresent(Bool.self, forKey: .mediaKeyToggle) ?? false
    }
}
