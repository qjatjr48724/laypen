import PencilKit
import Photos
import SwiftUI
import UIKit

enum AnnotationExportError: LocalizedError {
    case emptyCanvas
    case renderFailed
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .emptyCanvas: return "저장할 화면이 없습니다."
        case .renderFailed: return "이미지 생성에 실패했습니다."
        case .permissionDenied: return "사진 보관함 저장 권한이 필요합니다."
        case .saveFailed: return "사진 저장에 실패했습니다."
        }
    }
}

enum AnnotationExporter {
    /// 화면에 보이는 것과 같은 좌표계로 배경 + 흰색 상자 + 필기를 합성한다.
    static func compose(
        background: UIImage?,
        shapes: [WhiteRectShape],
        lines: [LineShape] = [],
        drawing: PKDrawing,
        canvasSize: CGSize,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        let width = max(1, canvasSize.width)
        let height = max(1, canvasSize.height)
        let logicalSize = CGSize(width: width, height: height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: logicalSize, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: logicalSize))

            if let background {
                let fitted = aspectFitRect(for: background.size, in: logicalSize)
                background.draw(in: fitted)
            }

            UIColor.white.setFill()
            for shape in shapes {
                let path = UIBezierPath(roundedRect: shape.rect, cornerRadius: 4)
                path.fill()
            }

            for line in lines {
                let path = UIBezierPath()
                path.move(to: line.start)
                path.addLine(to: line.end)
                path.lineWidth = line.width
                path.lineCapStyle = .round
                UIColor(Color(hex: line.colorHex)).setStroke()
                path.stroke()
            }

            let bounds = CGRect(origin: .zero, size: logicalSize)
            let ink = drawing.image(from: bounds, scale: scale)
            ink.draw(in: bounds)
        }
    }

    static func saveToPhotoLibrary(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AnnotationExportError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? AnnotationExportError.saveFailed)
                }
            })
        }
    }

    private static func aspectFitRect(for imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }
}
