import Foundation
import PencilKit

/// 획 데이터·Undo/Redo·로컬 저장. PencilKit drawing 바이너리를 사용한다.
final class StrokeStore {
    private(set) var drawing = PKDrawing()

    var hasContent: Bool { !drawing.strokes.isEmpty }

    func replace(_ drawing: PKDrawing) {
        self.drawing = drawing
    }

    func clear() {
        drawing = PKDrawing()
    }

    func loadFromDisk() {
        guard let url = AppGroup.containerURL?.appendingPathComponent(AppGroup.drawingFileName),
              let data = try? Data(contentsOf: url),
              let loaded = try? PKDrawing(data: data) else {
            return
        }
        drawing = loaded
    }

    func saveToDisk() {
        guard let url = AppGroup.containerURL?.appendingPathComponent(AppGroup.drawingFileName) else {
            return
        }
        let data = drawing.dataRepresentation()
        try? data.write(to: url, options: .atomic)
    }
}
