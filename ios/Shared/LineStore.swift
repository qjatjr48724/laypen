import Foundation

final class LineStore {
    private let fileName = "lines.json"

    func load() -> [LineShape] {
        guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let lines = try? JSONDecoder().decode([LineShape].self, from: data) else {
            return []
        }
        return lines
    }

    func save(_ lines: [LineShape]) {
        guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
              let data = try? JSONEncoder().encode(lines) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
