import CoreGraphics
import Foundation

struct CanvasViewport: Equatable {
    var zoomScale: CGFloat = 1
    var contentOffset: CGPoint = .zero

    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 5

    mutating func zoomIn(factor: CGFloat = 1.25) {
        zoomScale = min(Self.maxZoom, zoomScale * factor)
    }

    mutating func zoomOut(factor: CGFloat = 1.25) {
        zoomScale = max(Self.minZoom, zoomScale / factor)
        if zoomScale <= Self.minZoom + 0.01 {
            reset()
        }
    }

    mutating func reset() {
        zoomScale = Self.minZoom
        contentOffset = .zero
    }

    var percentLabel: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }
}
