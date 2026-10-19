import SwiftUI
import PencilKit

struct DrawingCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var canUndo: Bool
    @Binding var canRedo: Bool
    @Binding var viewport: CanvasViewport
    var tool: PKTool
    var isDrawingEnabled: Bool
    var allowsFingerDrawing: Bool = true

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        // 다크모드에서 검정 잉크가 흰색으로 뒤집히는 것을 막는다.
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.tool = tool
        canvas.minimumZoomScale = CanvasViewport.minZoom
        canvas.maximumZoomScale = CanvasViewport.maxZoom
        canvas.bouncesZoom = true
        canvas.bounces = true
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.isScrollEnabled = true
        canvas.isMultipleTouchEnabled = true
        canvas.drawingGestureRecognizer.isEnabled = isDrawingEnabled
        canvas.isUserInteractionEnabled = true
        context.coordinator.canvas = canvas
        context.coordinator.configureGestures(on: canvas)
        context.coordinator.observeUndoManager(canvas.undoManager)
        context.coordinator.publishUndoState()

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleUndo),
            name: .laypenUndo,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleRedo),
            name: .laypenRedo,
            object: nil
        )
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.overrideUserInterfaceStyle = .light
        if !context.coordinator.isMutatingDrawing, canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        canvas.tool = tool
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvas.drawingGestureRecognizer.isEnabled = isDrawingEnabled
        canvas.minimumZoomScale = CanvasViewport.minZoom
        canvas.maximumZoomScale = CanvasViewport.maxZoom
        context.coordinator.ensureTwoFingerPan(on: canvas)

        // contentSize를 매 프레임 강제로 넣으면 줌 후 팬이 막힌다. 1x일 때만 맞춘다.
        if canvas.bounds.width > 1, canvas.bounds.height > 1, abs(canvas.zoomScale - 1) < 0.01 {
            let size = canvas.bounds.size
            if abs(canvas.contentSize.width - size.width) > 1
                || abs(canvas.contentSize.height - size.height) > 1 {
                canvas.contentSize = size
            }
        }

        context.coordinator.parent = self
        context.coordinator.canvas = canvas
        // 제스처로 바뀐 뷰포트를 다시 setZoomScale로 밀어 넣지 않는다(좌상단 고정 원인).
        // 바인딩이 1x·오프셋0으로 리셋된 경우에만 캔버스에 반영.
        context.coordinator.applyIdentityViewportIfNeeded(on: canvas)
        context.coordinator.observeUndoManager(canvas.undoManager)
        context.coordinator.publishUndoState()
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.tearDownDrawingGesture()
        coordinator.tearDownUndoObservers()
        coordinator.cancelHoldTimer()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvasView
        weak var canvas: PKCanvasView?
        private weak var observedUndoManager: UndoManager?
        private var undoObserverTokens: [NSObjectProtocol] = []
        private var isApplyingExternalViewport = false
        private var didBindDrawingGesture = false

        /// 홀드→직선 스냅 상태
        private var holdTimer: Timer?
        private var lastGesturePoint: CGPoint?
        private var isStraightened = false
        private var straightenStart: CGPoint?
        private var strokeCountAtBegin = 0
        private var samplingStroke: PKStroke?
        /// 손을 뗀 직후 PencilKit이 획을 덮어쓰면 이 스냅샷으로 복구한다.
        private var pendingStraightCommit: PKDrawing?
        private(set) var isMutatingDrawing = false

        private let holdDuration: TimeInterval = 0.5
        private let moveResetThreshold: CGFloat = 4
        private let minStraightLength: CGFloat = 20
        private let straightThicknessScale: CGFloat = 0.82

        init(_ parent: DrawingCanvasView) {
            self.parent = parent
        }

        func configureGestures(on canvas: PKCanvasView) {
            ensureTwoFingerPan(on: canvas)
            guard !didBindDrawingGesture else { return }
            canvas.drawingGestureRecognizer.addTarget(self, action: #selector(handleDrawingGesture(_:)))
            didBindDrawingGesture = true
        }

        func ensureTwoFingerPan(on canvas: PKCanvasView) {
            let drawing = canvas.drawingGestureRecognizer
            for recognizer in canvas.gestureRecognizers ?? [] {
                guard let pan = recognizer as? UIPanGestureRecognizer else { continue }
                // 필기용 팬(1손가락)과 스크롤 팬을 구분
                if pan === drawing { continue }
                // drawingGestureRecognizer가 UIPan이 아닌 경우도 있어, 터치 수로 스크롤 팬만 제한
                if pan.minimumNumberOfTouches <= 1 && pan.maximumNumberOfTouches <= 1 {
                    // 일부 내부 제스처 — 건너뜀
                }
                pan.minimumNumberOfTouches = 2
                pan.maximumNumberOfTouches = 2
            }
        }

        func tearDownDrawingGesture() {
            canvas?.drawingGestureRecognizer.removeTarget(self, action: #selector(handleDrawingGesture(_:)))
            didBindDrawingGesture = false
        }

        // MARK: - Hold to straighten (GoodNotes-style)

        @objc private func handleDrawingGesture(_ gesture: UIGestureRecognizer) {
            guard parent.isDrawingEnabled else { return }
            if parent.tool is PKEraserTool {
                cancelHoldTimer()
                return
            }

            let location = gesture.location(in: canvas)

            switch gesture.state {
            case .began:
                resetStraightenState()
                strokeCountAtBegin = canvas?.drawing.strokes.count ?? 0
                if let canvas {
                    straightenStart = contentPoint(from: location, in: canvas)
                }
                lastGesturePoint = location
                scheduleHoldTimer()

            case .changed:
                if isStraightened {
                    enforceStraightStroke(endViewPoint: location)
                } else if let last = lastGesturePoint {
                    let moved = hypot(location.x - last.x, location.y - last.y)
                    if moved >= moveResetThreshold {
                        lastGesturePoint = location
                        scheduleHoldTimer()
                    }
                } else {
                    lastGesturePoint = location
                    scheduleHoldTimer()
                }

            case .ended, .cancelled, .failed:
                if isStraightened {
                    enforceStraightStroke(endViewPoint: location)
                    pendingStraightCommit = canvas?.drawing
                    resetStraightenState(clearPending: false)
                } else {
                    resetStraightenState()
                }

            default:
                break
            }
        }

        private func scheduleHoldTimer() {
            cancelHoldTimer()
            holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
                self?.snapCurrentStrokeToStraightLine()
            }
        }

        func cancelHoldTimer() {
            holdTimer?.invalidate()
            holdTimer = nil
        }

        private func resetStraightenState(clearPending: Bool = true) {
            cancelHoldTimer()
            isStraightened = false
            straightenStart = nil
            samplingStroke = nil
            lastGesturePoint = nil
            strokeCountAtBegin = 0
            if clearPending {
                pendingStraightCommit = nil
            }
        }

        private func snapCurrentStrokeToStraightLine() {
            guard let canvas,
                  canvas.drawingGestureRecognizer.state == .changed
                    || canvas.drawingGestureRecognizer.state == .began else { return }
            guard !(parent.tool is PKEraserTool) else { return }

            let endView = canvas.drawingGestureRecognizer.location(in: canvas)
            let end = contentPoint(from: endView, in: canvas)

            // 이번 제스처로 생긴 획만 대상으로 한다 (이전 필기는 prefix로 보존).
            let strokes = canvas.drawing.strokes
            let start: CGPoint
            if strokes.count > strokeCountAtBegin {
                let current = strokes[strokeCountAtBegin]
                samplingStroke = current
                start = StrokeStraightener.pathStart(of: current)
            } else if let began = straightenStart {
                start = began
            } else {
                return
            }

            straightenStart = start
            guard hypot(end.x - start.x, end.y - start.y) >= minStraightLength else { return }

            isStraightened = true
            enforceStraightStroke(endViewPoint: endView)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        /// 이전 획은 그대로 두고, 이번 제스처 획만 직선 하나로 유지한다.
        private func enforceStraightStroke(endViewPoint: CGPoint) {
            guard isStraightened, let start = straightenStart, let canvas else { return }
            guard let tool = inkingTool else { return }
            let end = contentPoint(from: endViewPoint, in: canvas)

            if samplingStroke == nil, canvas.drawing.strokes.count > strokeCountAtBegin {
                samplingStroke = canvas.drawing.strokes[strokeCountAtBegin]
            }

            let preserved = Array(canvas.drawing.strokes.prefix(strokeCountAtBegin))
            let straight = StrokeStraightener.makeLine(
                from: start,
                to: end,
                tool: tool,
                samplingStroke: samplingStroke,
                thicknessScale: straightThicknessScale
            )

            isMutatingDrawing = true
            canvas.drawing = PKDrawing(strokes: preserved + [straight])
            parent.drawing = canvas.drawing
            isMutatingDrawing = false
            publishUndoState()
        }

        private var inkingTool: PKInkingTool? {
            parent.tool as? PKInkingTool
        }

        private func contentPoint(from viewPoint: CGPoint, in canvas: PKCanvasView) -> CGPoint {
            let scale = max(canvas.zoomScale, 0.01)
            return CGPoint(
                x: (viewPoint.x + canvas.contentOffset.x) / scale,
                y: (viewPoint.y + canvas.contentOffset.y) / scale
            )
        }

        // MARK: - Viewport

        /// 외부에서 1x로 리셋된 경우에만 캔버스에 적용 (핀치/팬은 캔버스→바인딩 단방향)
        func applyIdentityViewportIfNeeded(on canvas: PKCanvasView) {
            let wantsIdentity = parent.viewport.zoomScale <= CanvasViewport.minZoom + 0.01
                && abs(parent.viewport.contentOffset.x) < 0.5
                && abs(parent.viewport.contentOffset.y) < 0.5
            guard wantsIdentity else { return }
            guard abs(canvas.zoomScale - 1) > 0.01
                || abs(canvas.contentOffset.x) > 0.5
                || abs(canvas.contentOffset.y) > 0.5 else { return }

            isApplyingExternalViewport = true
            canvas.setZoomScale(1, animated: false)
            canvas.contentOffset = .zero
            if canvas.bounds.width > 1 {
                canvas.contentSize = canvas.bounds.size
            }
            isApplyingExternalViewport = false
        }

        private func publishViewport(from scrollView: UIScrollView) {
            guard !isApplyingExternalViewport else { return }
            let next = CanvasViewport(
                zoomScale: scrollView.zoomScale,
                contentOffset: scrollView.contentOffset
            )
            if parent.viewport != next {
                parent.viewport = next
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            publishViewport(from: scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishViewport(from: scrollView)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isMutatingDrawing else { return }

            if let pending = pendingStraightCommit {
                // 손을 뗀 뒤 PK가 직선을 지우고 임시 획을 넣는 경우 복구
                pendingStraightCommit = nil
                isMutatingDrawing = true
                canvasView.drawing = pending
                parent.drawing = pending
                isMutatingDrawing = false
                publishUndoState()
                return
            }

            if isStraightened {
                let point = canvasView.drawingGestureRecognizer.location(in: canvasView)
                enforceStraightStroke(endViewPoint: point)
                return
            }

            parent.drawing = canvasView.drawing
            publishUndoState()
        }

        @objc func handleUndo() {
            canvas?.undoManager?.undo()
            publishUndoState()
        }

        @objc func handleRedo() {
            canvas?.undoManager?.redo()
            publishUndoState()
        }

        func observeUndoManager(_ undoManager: UndoManager?) {
            guard observedUndoManager !== undoManager else { return }
            tearDownUndoObservers()
            observedUndoManager = undoManager
            guard let undoManager else { return }

            let names: [Notification.Name] = [
                .NSUndoManagerDidUndoChange,
                .NSUndoManagerDidRedoChange,
                .NSUndoManagerDidCloseUndoGroup,
                .NSUndoManagerCheckpoint
            ]
            for name in names {
                let token = NotificationCenter.default.addObserver(
                    forName: name,
                    object: undoManager,
                    queue: .main
                ) { [weak self] _ in
                    self?.publishUndoState()
                }
                undoObserverTokens.append(token)
            }
        }

        func tearDownUndoObservers() {
            for token in undoObserverTokens {
                NotificationCenter.default.removeObserver(token)
            }
            undoObserverTokens.removeAll()
            observedUndoManager = nil
        }

        func publishUndoState() {
            let manager = canvas?.undoManager
            let nextUndo = manager?.canUndo ?? false
            let nextRedo = manager?.canRedo ?? false
            if parent.canUndo != nextUndo {
                parent.canUndo = nextUndo
            }
            if parent.canRedo != nextRedo {
                parent.canRedo = nextRedo
            }
        }
    }
}

struct AnnotatedCanvas: View {
    @Binding var drawing: PKDrawing
    @Binding var shapes: [WhiteRectShape]
    @Binding var lines: [LineShape]
    @Binding var selectedShapeID: UUID?
    @Binding var selectedLineID: UUID?
    @Binding var canUndo: Bool
    @Binding var canRedo: Bool
    @Binding var viewport: CanvasViewport
    var layoutAnchorSize: CGSize
    var tool: PKTool
    var isDrawingEnabled: Bool
    var allowsFingerDrawing: Bool = true
    var isPlacingWhiteRect: Bool
    var backgroundImage: UIImage?
    var onShapesChanged: () -> Void
    var onLinesChanged: () -> Void
    var onWhiteRectPlacementFinished: () -> Void
    var onCanvasSizeChange: ((CGSize) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let anchor = layoutAnchorSize.width > 1 ? layoutAnchorSize : viewSize
            let scale: CGFloat = {
                guard layoutAnchorSize.width > 1, layoutAnchorSize.height > 1,
                      viewSize.width > 1, viewSize.height > 1 else { return 1 }
                return min(viewSize.width / layoutAnchorSize.width, viewSize.height / layoutAnchorSize.height)
            }()
            // 리사이즈 프리뷰 중에는 좌표가 아직 bake 전이므로 입력은 잠시 막는다.
            let isLiveResizing = abs(scale - 1) >= 0.012

            ZStack {
                transformedContent(size: anchor) {
                    if let backgroundImage {
                        Image(uiImage: backgroundImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Color(uiColor: .secondarySystemBackground)
                    }
                }

                transformedContent(size: anchor) {
                    WhiteboardLayer(
                        shapes: $shapes,
                        selectedID: $selectedShapeID,
                        isDrawingEnabled: isDrawingEnabled && !isLiveResizing,
                        isPlacing: isPlacingWhiteRect && !isLiveResizing,
                        onPlacementFinished: onWhiteRectPlacementFinished,
                        onShapesChanged: onShapesChanged
                    )
                }
                .zIndex(isPlacingWhiteRect ? 3 : (isDrawingEnabled ? 0 : 2))

                transformedContent(size: anchor) {
                    LineBoardLayer(
                        lines: $lines,
                        selectedID: $selectedLineID,
                        isDrawingEnabled: isDrawingEnabled && !isLiveResizing,
                        isPlacing: false,
                        draftColorHex: "#000000",
                        draftWidth: 5,
                        onPlacementFinished: {},
                        onLinesChanged: onLinesChanged
                    )
                }
                .allowsHitTesting(!isPlacingWhiteRect && !isLiveResizing)
                .zIndex(isDrawingEnabled && !isPlacingWhiteRect ? 0 : 2)

                DrawingCanvasView(
                    drawing: $drawing,
                    canUndo: $canUndo,
                    canRedo: $canRedo,
                    viewport: $viewport,
                    tool: tool,
                    isDrawingEnabled: isDrawingEnabled && !isPlacingWhiteRect && !isLiveResizing,
                    allowsFingerDrawing: allowsFingerDrawing
                )
                .frame(width: anchor.width, height: anchor.height)
                .allowsHitTesting(!isPlacingWhiteRect && !isLiveResizing)
                .zIndex(1)
            }
            .frame(width: anchor.width, height: anchor.height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
            .clipped()
            // Split View 드래그 중에도 비율이 부드럽게 따라가도록
            .animation(
                .interactiveSpring(response: 0.32, dampingFraction: 0.92, blendDuration: 0.1),
                value: scale
            )
            .onAppear { onCanvasSizeChange?(viewSize) }
            .onChange(of: viewSize) { _, newSize in
                onCanvasSizeChange?(newSize)
            }
        }
    }

    private func transformedContent<Content: View>(
        size: CGSize,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: size.width, height: size.height)
            .scaleEffect(viewport.zoomScale, anchor: .topLeading)
            .offset(x: -viewport.contentOffset.x, y: -viewport.contentOffset.y)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
    }
}
