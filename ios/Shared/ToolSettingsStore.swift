import Foundation

final class ToolSettingsStore {
    private let fileName = "tool-settings.json"

    func load() -> ToolSettings {
        guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(ToolSettings.self, from: data) else {
            return ToolSettings()
        }
        return settings
    }

    func save(_ settings: ToolSettings) {
        guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
              let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
