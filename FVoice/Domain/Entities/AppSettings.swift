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
        case .whisper: return "Whisper · on-device model"
        case .apple: return "Apple SpeechTranscriber · minimal RAM (system managed)"
        }
    }
}

enum WhisperModel: String, Codable, CaseIterable, Identifiable {
    case turbo
    case small
    case base
    var id: String { rawValue }
    var label: String {
        switch self {
        case .turbo: return "Large-v3 turbo · best accuracy · ~2 GB RAM"
        case .small: return "Small · ~600 MB RAM"
        case .base: return "Base · fastest · ~250 MB RAM"
        }
    }
    /// WhisperKit model variant name (always multilingual, never .en).
    var variant: String {
        switch self {
        case .turbo: return "openai_whisper-large-v3-v20240930_turbo"
        case .small: return "openai_whisper-small"
        case .base: return "openai_whisper-base"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var language: String = "pt"          // "auto" = detect (opt-in only)
    var insertMode: InsertMode = .typing
    var autoEnter: Bool = false          // press Return after inserting
    var keyChord: KeyChord = .optionSpace
    var launchAtLogin: Bool = false
    var engine: EngineChoice = .whisper
    var whisperModel: WhisperModel = .turbo
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
    /// Set to true when the first-launch setup assistant finishes.
    var hasCompletedOnboarding: Bool = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case language, insertMode, autoEnter, keyChord, launchAtLogin, engine, hookScript, copyToClipboard
        case vocabulary, preferredMicUID, pushToTalk, whisperModel, hasCompletedOnboarding
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
        engine = try c.decodeIfPresent(EngineChoice.self, forKey: .engine) ?? .whisper
        hookScript = try c.decodeIfPresent(String.self, forKey: .hookScript)
            ?? "echo \"{{text}}\" >> ~/fvoice-hook.log"
        copyToClipboard = try c.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? false
        vocabulary = try c.decodeIfPresent(String.self, forKey: .vocabulary) ?? ""
        preferredMicUID = try c.decodeIfPresent(String.self, forKey: .preferredMicUID) ?? ""
        pushToTalk = try c.decodeIfPresent(Bool.self, forKey: .pushToTalk) ?? false
        let rawModel = try c.decodeIfPresent(String.self, forKey: .whisperModel)
        whisperModel = rawModel.flatMap(WhisperModel.init(rawValue:)) ?? .turbo
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
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
        try c.encode(engine, forKey: .engine)
        try c.encode(hookScript, forKey: .hookScript)
        try c.encode(copyToClipboard, forKey: .copyToClipboard)
        try c.encode(vocabulary, forKey: .vocabulary)
        try c.encode(preferredMicUID, forKey: .preferredMicUID)
        try c.encode(pushToTalk, forKey: .pushToTalk)
        try c.encode(whisperModel, forKey: .whisperModel)
        try c.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
    }
}
