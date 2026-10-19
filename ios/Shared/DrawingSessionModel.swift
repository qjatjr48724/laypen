import Foundation
import PencilKit
import SwiftUI
import UIKit

@MainActor
final class DrawingSessionModel: ObservableObject {
    @Published var backgroundImage: UIImage?
    @Published var drawing = PKDrawing()
    @Published var settings = ToolSettings()
    @Published var isMenuOpen = false
    @Published var showClearConfirm = false
    @Published var showClearInkConfirm = false
    @Published var shapes: [WhiteRectShape] = []
    @Published var lines: [LineShape] = []
    @Published var selectedShapeID: UUID?
    @Published var selectedLineID: UUID?
    @Published var isPlacingWhiteRect = false
    @Published var canvasSize: CGSize = .zero
    /// 필기·상자 좌표가 작성된 기준 크기. 창 리사이즈 중에는 이 크기 기준으로 부드럽게 스케일한다.
    @Published var layoutAnchorSize: CGSize = .zero
    @Published var viewport = CanvasViewport()
    private var isScalingLayout = false
    private var layoutBakeTask: Task<Void, Never>?
    @Published var isSavingPhoto = false
    @Published var isPreparingShare = false
    @Published var saveMessage: String?
    @Published var shareImage: UIImage?
    @Published var canUndo = false
    @Published var canRedo = false

    private let strokeStore = StrokeStore()
    private let sessionStore = SessionStore()
    private let shapeStore = ShapeStore()
    private let lineStore = LineStore()
    private let toolSettingsStore = ToolSettingsStore()

    var currentTool: PKTool {
        settings.makeTool(for: settings.selectedTool)
    }

    func bootstrap() {
        settings = toolSettingsStore.load()
        strokeStore.loadFromDisk()
        drawing = strokeStore.drawing
        shapes = shapeStore.load()
        lines = lineStore.load()
        if !consumePendingShareIfNeeded() {
            backgroundImage = sessionStore.loadBackground()
        }
    }

    /// 공유 확장에서 넘긴 이미지를 불러와 배경으로 설정. 성공 시 true.
    @discardableResult
    func consumePendingShareIfNeeded() -> Bool {
        guard let pending = ShareHandoff.loadPendingImage() else { return false }
        setBackground(pending)
        ShareHandoff.clearPendingImage()
        isMenuOpen = false
        return true
    }

    func setBackground(_ image: UIImage) {
        backgroundImage = image
        sessionStore.saveBackground(image)
        viewport.reset()
    }

    /// 창 크기 변경: 실시간으로는 부드럽게 스케일하고, 손을 떼면 좌표를 확정한다.
    func noteCanvasSize(_ size: CGSize) {
        guard !isScalingLayout else { return }
        canvasSize = size

        if layoutAnchorSize.width < 1 || layoutAnchorSize.height < 1 {
            layoutAnchorSize = size
            return
        }

        layoutBakeTask?.cancel()
        layoutBakeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            commitLayoutScaleIfNeeded()
        }
    }

    private func commitLayoutScaleIfNeeded() {
        let size = canvasSize
        let anchor = layoutAnchorSize
        guard !isScalingLayout,
              anchor.width > 1, anchor.height > 1,
              size.width > 1, size.height > 1 else { return }

        let scale = min(size.width / anchor.width, size.height / anchor.height)
        guard abs(scale - 1) >= 0.012 else {
            layoutAnchorSize = size
            return
        }

        isScalingLayout = true
        defer { isScalingLayout = false }

        // bake 직후 scaleEffect가 1로 보간되며 한 번 더 줄어들지 않게 애니메이션 차단
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            applyLayoutScale(scale)
            layoutAnchorSize = size
        }
    }

    private func applyLayoutScale(_ scale: CGFloat) {
        drawing = drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
        shapes = shapes.map { shape in
            var next = shape
            next.x *= scale
            next.y *= scale
            next.width *= scale
            next.height *= scale
            return next
        }
        lines = lines.map { line in
            var next = line
            next.x1 *= scale
            next.y1 *= scale
            next.x2 *= scale
            next.y2 *= scale
            next.width = max(1, next.width * scale)
            return next
        }
        viewport.contentOffset = CGPoint(
            x: viewport.contentOffset.x * scale,
            y: viewport.contentOffset.y * scale
        )
        persist()
    }

    func persist() {
        strokeStore.replace(drawing)
        strokeStore.saveToDisk()
        shapeStore.save(shapes)
        lineStore.save(lines)
        toolSettingsStore.save(settings)
        sessionStore.saveMetadata(
            SessionMetadata(updatedAt: Date(), hasBackgroundImage: backgroundImage != nil)
        )
    }

    func persistSettings() {
        toolSettingsStore.save(settings)
    }

    func beginWhiteRectPlacement() {
        isPlacingWhiteRect = true
        settings.isDrawingEnabled = false
        isMenuOpen = false
        selectedShapeID = nil
        selectedLineID = nil
    }

    func endWhiteRectPlacement() {
        isPlacingWhiteRect = false
    }

    func requestClearInk() {
        showClearInkConfirm = true
    }

    func clearInkConfirmed() {
        drawing = PKDrawing()
        persist()
    }

    func undo() {
        NotificationCenter.default.post(name: .laypenUndo, object: nil)
    }

    func redo() {
        NotificationCenter.default.post(name: .laypenRedo, object: nil)
    }

    func clearAllConfirmed() {
        drawing = PKDrawing()
        shapes = []
        lines = []
        selectedShapeID = nil
        selectedLineID = nil
        persist()
    }

    func composedAnnotationImage() -> UIImage? {
        guard canvasSize.width > 1, canvasSize.height > 1 else { return nil }
        return AnnotationExporter.compose(
            background: backgroundImage,
            shapes: shapes,
            lines: lines,
            drawing: drawing,
            canvasSize: canvasSize
        )
    }

    func saveAnnotatedPhoto() async {
        guard !isSavingPhoto else { return }
        guard let image = composedAnnotationImage() else {
            saveMessage = AnnotationExportError.emptyCanvas.localizedDescription
            return
        }

        isSavingPhoto = true
        defer { isSavingPhoto = false }

        do {
            try await AnnotationExporter.saveToPhotoLibrary(image)
            saveMessage = "사진에 저장했습니다."
            isMenuOpen = false
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    func prepareShare() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        guard let image = composedAnnotationImage() else {
            saveMessage = AnnotationExportError.emptyCanvas.localizedDescription
            return
        }
        shareImage = image
        isMenuOpen = false
    }
}

extension Notification.Name {
    static let laypenUndo = Notification.Name("laypen.undo")
    static let laypenRedo = Notification.Name("laypen.redo")
}
