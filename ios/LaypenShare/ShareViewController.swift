import UIKit
import UniformTypeIdentifiers
import SwiftUI
import PhotosUI

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadSharedImage()
    }

    private func loadSharedImage() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            finish()
            return
        }

        let imageType = UTType.image.identifier
        guard provider.hasItemConformingToTypeIdentifier(imageType) else {
            finish()
            return
        }

        provider.loadItem(forTypeIdentifier: imageType, options: nil) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let image = Self.image(from: item)
                if let image {
                    ShareHandoff.savePendingImage(image)
                    self.openHostAppOrPresentDrawing(with: image)
                } else {
                    self.finish()
                }
            }
        }
    }

    /// 가능하면 메인 Laypen 앱을 열고, 실패하면 확장 안에서 필기 UI를 연다.
    private func openHostAppOrPresentDrawing(with image: UIImage) {
        let url = ShareHandoff.importURL
        let canOpen = extensionContext != nil
        guard canOpen else {
            presentDrawing(for: image)
            return
        }

        extensionContext?.open(url) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    self.finish()
                } else {
                    // 일부 환경에서 open이 거부되면 기존처럼 확장 UI로 필기
                    self.presentDrawing(for: image)
                }
            }
        }
    }

    private func presentDrawing(for image: UIImage) {
        let model = DrawingSessionModel()
        model.setBackground(image)
        let root = ShareDrawingView(model: model) { [weak self] in
            self?.finish()
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private static func image(from item: NSSecureCoding?) -> UIImage? {
        if let image = item as? UIImage {
            return image
        }
        if let url = item as? URL, let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        if let data = item as? Data {
            return UIImage(data: data)
        }
        return nil
    }
}

private struct ShareDrawingView: View {
    @ObservedObject var model: DrawingSessionModel
    var onDone: () -> Void
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ZStack {
                AnnotatedCanvas(
                    drawing: $model.drawing,
                    shapes: $model.shapes,
                    lines: $model.lines,
                    selectedShapeID: $model.selectedShapeID,
                    selectedLineID: $model.selectedLineID,
                    canUndo: $model.canUndo,
                    canRedo: $model.canRedo,
                    viewport: $model.viewport,
                    tool: model.currentTool,
                    isDrawingEnabled: model.settings.isDrawingEnabled,
                    allowsFingerDrawing: model.settings.allowsFingerDrawing,
                    isPlacingWhiteRect: model.isPlacingWhiteRect,
                    backgroundImage: model.backgroundImage,
                    onShapesChanged: { model.persist() },
                    onLinesChanged: { model.persist() },
                    onWhiteRectPlacementFinished: { model.endWhiteRectPlacement() },
                    onCanvasSizeChange: { model.canvasSize = $0 }
                )
                .ignoresSafeArea(edges: .bottom)

                EdgeSnappingDraggable {
                    FloatingToolbar(
                        settings: $model.settings,
                        isMenuOpen: $model.isMenuOpen,
                        photoItem: $photoItem,
                        isPlacingWhiteRect: model.isPlacingWhiteRect,
                        isSavingPhoto: model.isSavingPhoto,
                        isPreparingShare: model.isPreparingShare,
                        canUndo: model.canUndo,
                        canRedo: model.canRedo,
                        onUndo: { model.undo() },
                        onRedo: { model.redo() },
                        onClearAll: { model.showClearConfirm = true },
                        onClearInk: { model.requestClearInk() },
                        onAddWhiteRect: { model.beginWhiteRectPlacement() },
                        onSavePhoto: {
                            Task { await model.saveAnnotatedPhoto() }
                        },
                        onExportShare: {
                            Task { await model.prepareShare() }
                        }
                    )
                }
            }
            .navigationTitle("Laypen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        model.persist()
                        onDone()
                    }
                }
            }
            .confirmationDialog("필기와 도형을 모두 삭제할까요?", isPresented: $model.showClearConfirm, titleVisibility: .visible) {
                Button("전체 삭제", role: .destructive) {
                    model.clearAllConfirmed()
                }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog("필기만 삭제할까요? (상자는 유지)", isPresented: $model.showClearInkConfirm, titleVisibility: .visible) {
                Button("필기만 삭제", role: .destructive) {
                    model.clearInkConfirmed()
                }
                Button("취소", role: .cancel) {}
            }
            .alert("알림", isPresented: Binding(
                get: { model.saveMessage != nil },
                set: { if !$0 { model.saveMessage = nil } }
            )) {
                Button("확인", role: .cancel) { model.saveMessage = nil }
            } message: {
                Text(model.saveMessage ?? "")
            }
            .laypenShareSheet(image: $model.shareImage)
            .onChange(of: model.drawing) { _, _ in
                model.persist()
            }
            .onChange(of: model.settings) { _, _ in
                model.persistSettings()
            }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    guard let newItem,
                          let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    model.setBackground(image)
                    model.isMenuOpen = false
                    photoItem = nil
                }
            }
        }
    }
}
