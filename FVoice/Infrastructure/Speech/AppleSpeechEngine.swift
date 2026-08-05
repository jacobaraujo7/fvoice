import AVFoundation
import Foundation
import Speech

/// TranscriptionEngine backed by Apple's on-device SpeechAnalyzer /
/// SpeechTranscriber (macOS 26+). Language assets are downloaded and managed
/// by the system.
@available(macOS 26.0, *)
final class AppleSpeechEngine: TranscriptionEngine {
    enum EngineError: Error {
        case localeUnsupported(String)
    }

    /// Locales whose assets were already verified this session.
    private var verifiedLocales = Set<String>()

    private static func locale(for language: String) -> Locale {
        let identifiers = [
            "pt": "pt-BR", "en": "en-US", "es": "es-ES", "fr": "fr-FR",
            "de": "de-DE", "it": "it-IT", "ja": "ja-JP", "ko": "ko-KR",
            "zh": "zh-CN", "ru": "ru-RU",
        ]
        // "auto" is unsupported here; fall back to the system language.
        if let identifier = identifiers[language] {
            return Locale(identifier: identifier)
        }
        return Locale.current
    }

    func prepare(onProgress: @escaping (Double) -> Void) async throws {
        try await ensureAssets(for: Self.locale(for: "pt"))
        DebugLog.log("apple speech assets ready")
    }

    func transcribe(samples: [Float], language: String, vocabulary: String) async throws -> String {
        // SpeechAnalyzer's file API is the stable path; write the samples to a
        // throwaway temp file and delete it right after.
        let wavURL = try Self.writeTempWav(samples: samples)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let locale = Self.locale(for: language)
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) else {
            throw EngineError.localeUnsupported(locale.identifier)
        }
        try await ensureAssets(for: locale)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        let file = try AVAudioFile(forReading: wavURL)
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let text = try await collector.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        DebugLog.log("apple transcription: \(text)")
        return text
    }

    private static func writeTempWav(samples: [Float]) throws -> URL {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                   channels: 1, interleaved: false)!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fvoice-\(UUID().uuidString).wav")
        var settings = format.settings
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMBitDepthKey] = 16
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                      frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
        return url
    }

    private func ensureAssets(for locale: Locale) async throws {
        guard !verifiedLocales.contains(locale.identifier) else { return }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            DebugLog.log("downloading apple speech assets for \(locale.identifier)…")
            try await request.downloadAndInstall()
        }
        verifiedLocales.insert(locale.identifier)
    }
}
