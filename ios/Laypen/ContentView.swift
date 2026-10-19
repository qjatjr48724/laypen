import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var session = DrawingSessionModel()
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            AnnotatedCanvas(
                drawing: $session.drawing,
                shapes: $session.shapes,
                lines: $session.lines,
                selectedShapeID: $session.selectedShapeID,
                selectedLineID: $session.selectedLineID,
                canUndo: $session.canUndo,
                canRedo: $session.canRedo,
                viewport: $session.viewport,
                layoutAnchorSize: session.layoutAnchorSize,
                tool: session.currentTool,
                isDrawingEnabled: session.settings.isDrawingEnabled,
                allowsFingerDrawing: session.settings.allowsFingerDrawing,
                isPlacingWhiteRect: session.isPlacingWhiteRect,
                backgroundImage: session.backgroundImage,
                onShapesChanged: { session.persist() },
                onLinesChanged: { session.persist() },
                onWhiteRectPlacementFinished: { session.endWhiteRectPlacement() },
                onCanvasSizeChange: { session.noteCanvasSize($0) }
            )
            .ignoresSafeArea()

            if session.isPlacingWhiteRect {
                VStack {
                    Text("드래그로 상자 크기 지정")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThickMaterial, in: Capsule())
                        .padding(.top, 12)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            EdgeSnappingDraggable { maxHeight in
                FloatingToolbar(
                    settings: $session.settings,
                    isMenuOpen: $session.isMenuOpen,
                    photoItem: $photoItem,
                    isPlacingWhiteRect: session.isPlacingWhiteRect,
                    isSavingPhoto: session.isSavingPhoto,
                    isPreparingShare: session.isPreparingShare,
                    canUndo: session.canUndo,
                    canRedo: session.canRedo,
                    onUndo: { session.undo() },
                    onRedo: { session.redo() },
                    onClearAll: { session.showClearConfirm = true },
                    onClearInk: { session.requestClearInk() },
                    onAddWhiteRect: { session.beginWhiteRectPlacement() },
                    onSavePhoto: {
                        Task { await session.saveAnnotatedPhoto() }
                    },
                    onExportShare: {
                        Task { await session.prepareShare() }
                    },
                    availableHeight: maxHeight
                )
            }
        }
        .onAppear {
            session.bootstrap()
        }
        .onOpenURL { _ in
            session.consumePendingShareIfNeeded()
        }
        .onChange(of: session.drawing) { _, _ in
            session.persist()
        }
        .onChange(of: session.settings) { _, _ in
            session.persistSettings()
        }
        .onChange(of: photoItem) { _, newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                session.setBackground(image)
                session.isMenuOpen = false
                photoItem = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            session.persist()
        }
        .confirmationDialog("필기와 도형을 모두 삭제할까요?", isPresented: $session.showClearConfirm, titleVisibility: .visible) {
            Button("전체 삭제", role: .destructive) {
                session.clearAllConfirmed()
            }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("필기만 삭제할까요? (상자는 유지)", isPresented: $session.showClearInkConfirm, titleVisibility: .visible) {
            Button("필기만 삭제", role: .destructive) {
                session.clearInkConfirmed()
            }
            Button("취소", role: .cancel) {}
        }
        .alert("알림", isPresented: Binding(
            get: { session.saveMessage != nil },
            set: { if !$0 { session.saveMessage = nil } }
        )) {
            Button("확인", role: .cancel) { session.saveMessage = nil }
        } message: {
            Text(session.saveMessage ?? "")
        }
        .laypenShareSheet(image: $session.shareImage)
    }
}
