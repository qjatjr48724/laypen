import CoreGraphics
import Foundation

struct WhiteRectShape: Identifiable, Codable, Equatable {
    var id: UUID
    /// Canvas 좌표계에서의 프레임 (왼쪽 위 기준)
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var rect: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = newValue.size.width
            height = newValue.size.height
        }
    }

    static func make(from draft: CGRect) -> WhiteRectShape {
        let normalized = draft.standardized
        return WhiteRectShape(
            id: UUID(),
            x: normalized.minX,
            y: normalized.minY,
            width: max(40, normalized.width),
            height: max(40, normalized.height)
        )
    }
}
