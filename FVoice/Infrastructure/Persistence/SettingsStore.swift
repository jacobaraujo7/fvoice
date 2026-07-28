import Foundation
import ServiceManagement

/// Persists AppSettings in UserDefaults and mirrors them to
/// ~/.fvoice/config.json so they can be edited outside the app.
@MainActor
final class SettingsStore: ObservableObject {
    private static let defaultsKey = "app_settings"
    private static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".fvoice/config.json")

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
            if settings.launchAtLogin != oldValue.launchAtLogin {
                applyLaunchAtLogin()
            }
        }
    }

    init() {
        // config.json wins over UserDefaults so external edits take effect.
        if let data = try? Data(contentsOf: Self.configURL),
           let fromFile = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = fromFile
        } else if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
                  let fromDefaults = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = fromDefaults
        } else {
            settings = AppSettings()
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        try? FileManager.default.createDirectory(
            at: Self.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.configURL)
    }

    private func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DebugLog.log("launch at login toggle failed: \(error)")
        }
    }
}
