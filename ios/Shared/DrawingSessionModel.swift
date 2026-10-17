import Foundation
import PencilKit
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
    @Published var viewport = CanvasViewport()
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
