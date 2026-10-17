import CoreGraphics
import PencilKit
import UIKit

enum StrokeStraightener {
    /// PencilKit에 직접 넣은 획은 이 값보다 작으면 렌더에서 종종 탈락한다.
    private static let minRenderableSize: CGFloat = 4

    /// 자유획 샘플 두께를 기준으로 straighten. `thicknessScale`로 살짝 얇게 조절한다.
    static func makeLine(
        from start: CGPoint,
        to end: CGPoint,
        tool: PKInkingTool,
        samplingStroke: PKStroke?,
        thicknessScale: CGFloat = 0.82
    ) -> PKStroke {
        let sampled = samplingStroke.flatMap(averageSize)
        let base = sampled ?? CGSize(width: tool.width, height: tool.width)

        // 설정 두께감은 유지하되, 얇은 펜도 직선이 사라지지 않도록 하한을 둔다.
        let size = CGSize(
            width: max(minRenderableSize, base.width * thicknessScale),
            height: max(minRenderableSize, base.height * thicknessScale)
        )

        let inkType = samplingStroke?.ink.inkType ?? tool.ink.inkType
        let ink = PKInk(inkType, color: displayColor(for: tool.color))

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        let azimuth = atan2(dy, dx)
        let altitude = CGFloat.pi / 2

        // 얇을수록 점을 더 촘촘히 넣어 끊김/탈락을 줄인다.
        let stepLength: CGFloat = size.width < 6 ? 2 : 3
        let steps = max(16, Int(ceil(length / stepLength)))
        var points: [PKStrokePoint] = []
        points.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            points.append(
                PKStrokePoint(
                    location: CGPoint(x: start.x + dx * t, y: start.y + dy * t),
                    timeOffset: TimeInterval(t) * 0.12,
                    size: size,
                    opacity: 1,
                    force: 1,
                    azimuth: azimuth,
                    altitude: altitude
                )
            )
        }

        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: ink, path: path, transform: .identity)
    }

    static func pathStart(of stroke: PKStroke) -> CGPoint {
        stroke.path.interpolatedLocation(at: 0)
    }

    private static func displayColor(for toolColor: UIColor) -> UIColor {
        let resolved = toolColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
        return UIColor(red: r, green: g, blue: b, alpha: max(a, 1))
    }

    private static func averageSize(of stroke: PKStroke) -> CGSize? {
        let points = Array(stroke.path.interpolatedPoints(by: .parametricStep(0.2)))
        guard !points.isEmpty else { return nil }
        let total = points.reduce(CGSize.zero) { partial, point in
            CGSize(width: partial.width + point.size.width, height: partial.height + point.size.height)
        }
        let n = CGFloat(points.count)
        return CGSize(width: total.width / n, height: total.height / n)
    }
}
