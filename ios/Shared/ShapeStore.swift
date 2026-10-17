import Foundation

final class ShapeStore {
    private let fileName = "white-rects.json"

    func load() -> [WhiteRectShape] {
        guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let shapes = try? JSONDecoder().decode([WhiteRectShape].self, from: data) else {
            return []
        }
        return shapes
    }

    func save(_ shapes: [WhiteRectShape]) {
        guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
              let data = try? JSONEncoder().encode(shapes) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
