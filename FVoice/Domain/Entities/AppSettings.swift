import Foundation

enum InsertMode: String, Codable, CaseIterable, Identifiable {
    case typing
    case hook
    var id: String { rawValue }
    var label: String {
        switch self {
        case .typing: return "Typing (recommended)"
        case .hook: return "Hook (run script)"
        }
    }
}

/// A user-recordable global shortcut: one key plus at least one modifier.
struct KeyChord: Codable, Equatable {
    var keyCode: UInt16
    var command = false
    var option = false
    var control = false
    var shift = false

    static let optionSpace = KeyChord(keyCode: 49, option: true)

    var display: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt16) -> String {
        keyNames[code] ?? "key \(code)"
    }

    private static let keyNames: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
        35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
        13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
        26: "7", 28: "8", 25: "9",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15",
    ]
}

enum EngineChoice: String, Codable, CaseIterable, Identifiable {
    case whisper
    case apple
    var id: String { rawValue }
    var label: String {
        switch self {
        case .whisper: return "Whisper (large-v3 turbo)"
        case .apple: return "Apple SpeechTranscriber"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var language: String = "pt"          // "auto" = detect (opt-in only)
    var insertMode: InsertMode = .typing
    var autoEnter: Bool = false          // press Return after inserting
    var keyChord: KeyChord = .optionSpace
    var launchAtLogin: Bool = false
    /// AirPods stem press (media Play/Pause) toggles recording. While on,
    /// the press no longer controls media playback.
    var mediaKeyToggle: Bool = false
    var engine: EngineChoice = .whisper
    /// Also copy every transcription to the clipboard.
    var copyToClipboard: Bool = false
    /// Comma-separated jargon fed to Whisper as an initial prompt.
    var vocabulary: String = ""
    /// Input device UID; empty means system default.
    var preferredMicUID: String = ""
    /// Hold the shortcut to record, release to transcribe.
    var pushToTalk: Bool = false
    /// Shell script run by the hook insert mode. {{text}} is replaced by the
    /// transcription (also available as $FVOICE_TEXT).
    var hookScript: String = "echo \"{{text}}\" >> ~/fvoice-hook.log"

    init() {}

    private enum CodingKeys: String, CodingKey {
        case language, insertMode, autoEnter, keyChord, launchAtLogin, mediaKeyToggle, engine, hookScript, copyToClipboard
        case vocabulary, preferredMicUID, pushToTalk
        case legacyHotkey = "hotkey"
    }

    // Tolerant decoding so config.json files from older versions keep working
    // when new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "pt"
        // Raw-string decode so removed modes (e.g. old "paste") fall back
        // instead of failing the whole settings file.
        let rawMode = try c.decodeIfPresent(String.self, forKey: .insertMode)
        insertMode = rawMode.flatMap(InsertMode.init(rawValue:)) ?? .typing
        autoEnter = try c.decodeIfPresent(Bool.self, forKey: .autoEnter) ?? false
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        mediaKeyToggle = try c.decodeIfPresent(Bool.self, forKey: .mediaKeyToggle) ?? false
        engine = try c.decodeIfPresent(EngineChoice.self, forKey: .engine) ?? .whisper
        hookScript = try c.decodeIfPresent(String.self, forKey: .hookScript)
            ?? "echo \"{{text}}\" >> ~/fvoice-hook.log"
        copyToClipboard = try c.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? false
        vocabulary = try c.decodeIfPresent(String.self, forKey: .vocabulary) ?? ""
        preferredMicUID = try c.decodeIfPresent(String.self, forKey: .preferredMicUID) ?? ""
        pushToTalk = try c.decodeIfPresent(Bool.self, forKey: .pushToTalk) ?? false
        if let chord = try c.decodeIfPresent(KeyChord.self, forKey: .keyChord) {
            keyChord = chord
        } else {
            // Migrate the old preset enum.
            switch try c.decodeIfPresent(String.self, forKey: .legacyHotkey) {
            case "controlOptionSpace": keyChord = KeyChord(keyCode: 49, option: true, control: true)
            case "commandShiftSpace": keyChord = KeyChord(keyCode: 49, command: true, shift: true)
            default: keyChord = .optionSpace
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(language, forKey: .language)
        try c.encode(insertMode, forKey: .insertMode)
        try c.encode(autoEnter, forKey: .autoEnter)
        try c.encode(keyChord, forKey: .keyChord)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(mediaKeyToggle, forKey: .mediaKeyToggle)
        try c.encode(engine, forKey: .engine)
        try c.encode(hookScript, forKey: .hookScript)
        try c.encode(copyToClipboard, forKey: .copyToClipboard)
        try c.encode(vocabulary, forKey: .vocabulary)
        try c.encode(preferredMicUID, forKey: .preferredMicUID)
        try c.encode(pushToTalk, forKey: .pushToTalk)
    }
}
