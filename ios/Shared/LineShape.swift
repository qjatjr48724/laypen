import CoreGraphics
import Foundation

struct LineShape: Identifiable, Codable, Equatable {
    var id: UUID
    var x1: CGFloat
    var y1: CGFloat
    var x2: CGFloat
    var y2: CGFloat
    var colorHex: String
    var width: CGFloat

    var start: CGPoint {
        get { CGPoint(x: x1, y: y1) }
        set { x1 = newValue.x; y1 = newValue.y }
    }

    var end: CGPoint {
        get { CGPoint(x: x2, y: y2) }
        set { x2 = newValue.x; y2 = newValue.y }
    }

    var length: CGFloat {
        hypot(x2 - x1, y2 - y1)
    }

    static func make(
        from start: CGPoint,
        to end: CGPoint,
        colorHex: String,
        width: CGFloat
    ) -> LineShape {
        LineShape(
            id: UUID(),
            x1: start.x,
            y1: start.y,
            x2: end.x,
            y2: end.y,
            colorHex: colorHex,
            width: max(1, width)
        )
    }
}
