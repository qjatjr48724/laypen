import PhotosUI
import SwiftUI
import UIKit

struct MacLinkView: View {
    @Binding var settings: ToolSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MacLinkModel
    @State private var isMenuOpen = false
    @State private var photoItem: PhotosPickerItem?
    @State private var bannerText: String?
    @State private var bannerOpacity: Double = 0
    @State private var bannerTask: Task<Void, Never>?
    @State private var didShowConnectBanner = false

    init(settings: Binding<ToolSettings>) {
        _settings = settings
        _model = StateObject(wrappedValue: MacLinkModel(settings: settings.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isConnected {
                    connected
                } else {
                    pairing
                }
            }
            .navigationTitle("맥에 연결")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(model.isConnected ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        model.disconnect()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { model.start() }
        .onChange(of: model.settings) { _, newValue in
            if settings != newValue {
                settings = newValue
            }
        }
        .onChange(of: model.showsMacInk) { _, _ in
            model.sendInkVisibility()
        }
        .onChange(of: model.isConnected) { _, connected in
            if connected {
                showConnectBannerOnce()
            } else {
                bannerTask?.cancel()
                bannerText = nil
                bannerOpacity = 0
                didShowConnectBanner = false
            }
        }
        .onChange(of: model.settings.selectedTool) { _, tool in
            guard tool == .selection else { return }
            if model.controlsMac {
                model.setControlsMac(false)
            }
            if model.isPlacingWhiteRect {
                model.finishBoxPlacement()
                model.settings.isDrawingEnabled = true
            }
        }
        .onChange(of: model.settings.inputMode) { _, mode in
            if mode == .penAndHand, model.controlsMac {
                model.setControlsMac(false)
            }
        }
    }

    private var pairing: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text(model.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    model.refreshNearby()
                } label: {
                    if model.refreshCooldownRemaining > 0 {
                        Text("\(model.refreshCooldownRemaining)초")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .frame(minWidth: 36)
                    } else {
                        Label("새로고침", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.refreshCooldownRemaining > 0)
            }
            if model.nearby.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(model.nearby) { mac in
                    Button {
                        model.selectedID = mac.id
                    } label: {
                        HStack {
                            Text(mac.name)
                            Spacer()
                            if mac.isTrusted {
                                Text("저장됨")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if model.selectedID == mac.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            if model.asksForCode || !model.selectedMacIsTrusted {
                TextField("코드 4자리", text: Binding(
                    get: { model.code },
                    set: { model.setCode($0) }
                ))
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .font(.title2.monospacedDigit())
            } else {
                Text("이 맥은 저장되어 있어 코드 없이 연결됩니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("코드 입력", action: model.requestCodeEntry)
                        .buttonStyle(.bordered)
                }
            }
            HStack {
                Spacer()
                Button("연결", action: model.connect)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedID == nil || ((model.asksForCode || !model.selectedMacIsTrusted) && model.code.count != 4))
            }
            Spacer()
        }
        .padding(20)
    }

    private var connected: some View {
        ZStack {
            MacLinkCanvas(model: model)
                .ignoresSafeArea()
            EdgeSnappingDraggable { maxHeight in
                FloatingToolbar(
                    settings: $model.settings,
                    isMenuOpen: $isMenuOpen,
                    photoItem: $photoItem,
                    isPlacingWhiteRect: model.isPlacingWhiteRect,
                    canUndo: model.canUndo,
                    canRedo: model.canRedo,
                    onUndo: { model.undo() },
                    onRedo: { model.redo() },
                    onClearAll: { model.showClearConfirm = true },
                    onClearInk: { model.showClearInkConfirm = true },
                    onAddWhiteRect: {
                        model.beginBoxPlacement()
                        isMenuOpen = false
                    },
                    onSavePhoto: {},
                    onExportShare: {},
                    showsMacScreen: $model.showsMacScreen,
                    showsMacInk: $model.showsMacInk,
                    controlsMac: Binding(
                        get: { model.controlsMac },
                        set: { model.setControlsMac($0) }
                    ),
                    onDisconnect: { model.disconnect() },
                    showsPhotoActions: false,
                    availableHeight: maxHeight
                )
            }
            if let bannerText {
                Text(bannerText)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                    .opacity(bannerOpacity)
            }
        }
        .background(Color.black)
        .confirmationDialog("필기와 도형을 모두 삭제할까요?", isPresented: $model.showClearConfirm, titleVisibility: .visible) {
            Button("전체 삭제", role: .destructive) {
                model.clearAll()
            }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("필기만 삭제할까요? (상자는 유지)", isPresented: $model.showClearInkConfirm, titleVisibility: .visible) {
            Button("필기만 삭제", role: .destructive) {
                model.clearInk()
            }
            Button("취소", role: .cancel) {}
        }
    }

    /// 연결 직후 한 번만 3초 안내를 보여 주고, 천천히 사라지게 한다.
    private func showConnectBannerOnce() {
        guard !didShowConnectBanner else { return }
        didShowConnectBanner = true
        let message: String
        switch model.settings.inputMode {
        case .penAndHand:
            message = "펜으로 필기하고, 손가락으로 맥을 조작합니다. 두 손가락은 스크롤"
        case .pen:
            message = "펜으로 필기합니다. 맥 조작은 마우스 버튼을 켜세요"
        case .hand:
            message = "손으로 필기합니다. 맥 조작은 마우스 버튼을 켜세요"
        }
        bannerTask?.cancel()
        bannerText = message
        bannerOpacity = 0
        withAnimation(.easeOut(duration: 0.25)) {
            bannerOpacity = 1
        }
        bannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.7)) {
                bannerOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            bannerText = nil
        }
    }
}

struct MacLinkCanvas: UIViewRepresentable {
    var model: MacLinkModel

    func makeUIView(context: Context) -> MacLinkCanvasView {
        let view = MacLinkCanvasView()
        bind(view)
        return view
    }

    func updateUIView(_ uiView: MacLinkCanvasView, context: Context) {
        bind(uiView)
        if !model.controlsMac, model.settings.inputMode != .penAndHand {
            uiView.releaseControl()
        }
        if model.settings.selectedTool != .selection {
            uiView.clearInkSelection()
        }
    }

    private func bind(_ view: MacLinkCanvasView) {
        view.model = model
        model.onCanvasChange = { [weak view] in
            view?.setNeedsDisplay()
        }
        model.onInkEdited = { [weak view] in
            view?.clearInkSelection()
        }
        view.setNeedsDisplay()
    }
}

final class MacLinkCanvasView: UIView {
    weak var model: MacLinkModel?
    private var activeTouches = Set<ObjectIdentifier>()
    private var eraserCursor: CGPoint?
    private var isHovering = false
    private var holdTimer: Timer?
    private var straightenStart: CGPoint?
    private var lastGesturePoint: CGPoint?
    private var currentPoint: CGPoint?
    private var isStraightened = false
    private var edit: BoxEdit?
    private var editTouch: ObjectIdentifier?
    private var previewRect: CGRect?
    private var selectedBoxID: UUID?
    private var showTrash = false
    private var overTrash = false
    private var controlPoints: [ObjectIdentifier: CGPoint] = [:]
    private var pointerIsDown = false
    private var scrollCentroid: CGPoint?
    private var controlCursor: CGPoint?
    /// 이 비율을 넘으면 드래그를 시작하고, 더 낮아지면 버튼만 놓는다.
    private let dragPressOn: CGFloat = 0.34
    private let dragPressOff: CGFloat = 0.16
    private var cachedInk: UIImage?
    private var cachedStrokes: [LinkStroke] = []
    private var cachedInkFit: CGRect = .zero
    private var selectedStrokeIndices = IndexSet()
    private var inkGesture: InkGesture?
    private var selectionTouch: ObjectIdentifier?
    private var marqueeRect: CGRect?
    private var moveDelta = CGSize.zero

    private enum InkGesture {
        case marquee(start: CGPoint)
        case moving(start: CGPoint)
    }

    private enum BoxCorner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    private enum BoxEdit {
        case placing(start: CGPoint)
        case moving(id: UUID, origin: CGRect, start: CGPoint)
        case resizing(id: UUID, corner: BoxCorner, origin: CGRect, start: CGPoint)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .black
        contentMode = .redraw
        isOpaque = true
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        // 호버가 손가락 터치를 취소·지연시키지 않게 한다.
        hover.cancelsTouchesInView = false
        hover.delaysTouchesBegan = false
        hover.delaysTouchesEnded = false
        addGestureRecognizer(hover)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let model else { return }
        let fit = drawingRect(for: model)
        if model.showsMacScreen, let image = model.image {
            image.draw(in: fit)
        } else {
            UIColor(white: 0.86, alpha: 1).setFill()
            UIRectFill(bounds)
        }
        if model.showsMacInk {
            drawBoxes(model, fit: fit)
            if moveDelta != .zero, !selectedStrokeIndices.isEmpty {
                renderInk(shiftedStrokes(model.ink.strokes, fit: fit), fit: fit)?.draw(in: bounds)
            } else {
                inkLayer(model.ink.strokes, fit: fit)?.draw(in: bounds)
            }
            drawPlacementDraft()
            drawTrash()
            drawInkSelection(fit: fit)
        }
        if !model.showsMacScreen {
            let border = fit.insetBy(dx: 1, dy: 1)
            let path = UIBezierPath(rect: border)
            path.lineWidth = 1.5
            UIColor(white: 0.55, alpha: 1).setStroke()
            path.stroke()
        }
        drawEraserCursor()
        drawControlCursor()
    }

    private func inkLayer(_ strokes: [LinkStroke], fit: CGRect) -> UIImage? {
        if cachedInkFit == fit, cachedStrokes == strokes {
            return cachedInk
        }
        let image = renderInk(strokes, fit: fit)
        cachedInk = image
        cachedStrokes = strokes
        cachedInkFit = fit
        return image
    }

    private func drawControlCursor() {
        guard let model,
              model.controlsMac || model.settings.inputMode == .penAndHand,
              let center = controlCursor else { return }
        let dragging = pointerIsDown
        let side: CGFloat = dragging ? 18 : 14
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        let path = UIBezierPath(ovalIn: rect)
        (dragging ? UIColor.systemTeal : UIColor.white).setFill()
        path.fill()
        UIColor.black.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            isHovering = true
            eraserCursor = gesture.location(in: self)
        default:
            isHovering = false
            if activeTouches.isEmpty {
                eraserCursor = nil
            }
        }
        setNeedsDisplay()
    }

    private func drawEraserCursor() {
        guard let model, model.settings.selectedTool == .eraser, let center = eraserCursor else { return }
        let diameter = max(8, model.settings.eraserWidth)
        let rect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let path = UIBezierPath(ovalIn: rect)
        UIColor.white.withAlphaComponent(0.28).setFill()
        path.fill()
        UIColor.black.withAlphaComponent(0.72).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model else { return }
        if model.controlsMac {
            trackControl(touches, phase: .began)
            return
        }
        if routePenAndHand(touches, event: event, phase: .began) { return }
        if model.settings.selectedTool == .selection {
            beginInkSelection(touches)
            return
        }
        if model.isPlacingWhiteRect {
            guard edit == nil, let touch = touches.first else { return }
            let point = touch.location(in: self)
            editTouch = ObjectIdentifier(touch)
            edit = .placing(start: point)
            previewRect = CGRect(origin: point, size: .zero)
            setNeedsDisplay()
            return
        }
        if !model.settings.isDrawingEnabled {
            guard edit == nil, let touch = touches.first else { return }
            beginBoxEdit(touch, model: model)
            return
        }
        append(touches, event: event, phase: .began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if model?.controlsMac == true {
            trackControl(touches, phase: .moved)
            return
        }
        if routePenAndHand(touches, event: event, phase: .moved) { return }
        if model?.settings.selectedTool == .selection {
            updateInkSelection(touches)
            return
        }
        if updateBoxEdit(touches) { return }
        append(touches, event: event, phase: .moved)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if model?.controlsMac == true {
            trackControl(touches, phase: .ended)
            return
        }
        if routePenAndHand(touches, event: event, phase: .ended) { return }
        if model?.settings.selectedTool == .selection {
            finishInkSelection(touches, commit: true)
            return
        }
        if finishBoxEdit(touches, commit: true) { return }
        append(touches, event: event, phase: .ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if model?.controlsMac == true {
            trackControl(touches, phase: .cancelled)
            return
        }
        if routePenAndHand(touches, event: event, phase: .cancelled) { return }
        if model?.settings.selectedTool == .selection {
            finishInkSelection(touches, commit: false)
            return
        }
        if finishBoxEdit(touches, commit: false) { return }
        append(touches, event: event, phase: .ended)
    }

    /// 손+펜: 펜은 필기, 손가락(펜이 아닌 접촉)은 맥 조작.
    private func routePenAndHand(
        _ touches: Set<UITouch>,
        event: UIEvent?,
        phase: UITouch.Phase
    ) -> Bool {
        guard let model,
              model.settings.inputMode == .penAndHand,
              model.settings.selectedTool != .selection,
              !model.isPlacingWhiteRect,
              model.settings.isDrawingEnabled else { return false }
        // .direct만 보면 일부 기기/상황에서 손가락이 빠져 조작이 死는다. 펜만 제외한다.
        let fingers = Set(touches.filter { $0.type != .pencil })
        let pencils = Set(touches.filter { $0.type == .pencil })
        if !fingers.isEmpty {
            trackControl(fingers, phase: phase)
        }
        if !pencils.isEmpty {
            let strokePhase: StrokePhase
            switch phase {
            case .began: strokePhase = .began
            case .ended, .cancelled: strokePhase = .ended
            default: strokePhase = .moved
            }
            append(pencils, event: event, phase: strokePhase)
        }
        return true
    }

    private func trackControl(_ touches: Set<UITouch>, phase: UITouch.Phase) {
        guard let model else { return }
        let fit = drawingRect(for: model)
        guard fit.width > 1, fit.height > 1 else { return }
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let point = touch.location(in: self)
            switch phase {
            case .ended, .cancelled:
                controlPoints[id] = point
            default:
                controlPoints[id] = point
            }
        }
        if controlPoints.count >= 2 {
            if pointerIsDown {
                sendPointer(phase: PointerEvent.ended, fit: fit, point: controlCursor ?? touches.first?.location(in: self) ?? .zero)
                pointerIsDown = false
            }
            let points = Array(controlPoints.values)
            let centroid = CGPoint(
                x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
            )
            if let previous = scrollCentroid {
                sendPointer(
                    phase: PointerEvent.scroll,
                    fit: fit,
                    point: centroid,
                    dx: (centroid.x - previous.x) / fit.width,
                    dy: (centroid.y - previous.y) / fit.height
                )
            }
            scrollCentroid = centroid
            controlCursor = centroid
        } else if controlPoints.count == 1, let point = controlPoints.values.first {
            scrollCentroid = nil
            controlCursor = point
            let touch = touches.first { controlPoints[ObjectIdentifier($0)] != nil }
            if phase == .cancelled {
                if pointerIsDown {
                    sendPointer(phase: PointerEvent.cancelled, fit: fit, point: point)
                    pointerIsDown = false
                }
            } else if touch?.type == .pencil, phase != .ended {
                updatePencilPressure(touch!, point: point, fit: fit)
            } else if phase == .ended {
                if pointerIsDown {
                    sendPointer(phase: PointerEvent.ended, fit: fit, point: point)
                    pointerIsDown = false
                }
            } else if !pointerIsDown {
                sendPointer(phase: PointerEvent.began, fit: fit, point: point)
                pointerIsDown = true
            } else {
                sendPointer(phase: PointerEvent.moved, fit: fit, point: point)
            }
        } else {
            scrollCentroid = nil
            controlCursor = nil
            if pointerIsDown {
                sendPointer(phase: PointerEvent.ended, fit: fit, point: .zero)
                pointerIsDown = false
            }
        }
        if phase == .ended || phase == .cancelled {
            for touch in touches {
                controlPoints.removeValue(forKey: ObjectIdentifier(touch))
            }
            if controlPoints.isEmpty {
                scrollCentroid = nil
                if phase == .ended || phase == .cancelled {
                    controlCursor = nil
                }
            }
        }
        setNeedsDisplay()
    }

    private func updatePencilPressure(_ touch: UITouch, point: CGPoint, fit: CGRect) {
        let maximum = touch.maximumPossibleForce
        let pressure = maximum > 0 ? touch.force / maximum : 0
        let pressing = pointerIsDown ? pressure >= dragPressOff : pressure >= dragPressOn
        if pressing, !pointerIsDown {
            sendPointer(phase: PointerEvent.began, fit: fit, point: point)
            pointerIsDown = true
        } else if !pressing, pointerIsDown {
            sendPointer(phase: PointerEvent.ended, fit: fit, point: point)
            pointerIsDown = false
            sendPointer(phase: PointerEvent.hover, fit: fit, point: point)
        } else if pointerIsDown {
            sendPointer(phase: PointerEvent.moved, fit: fit, point: point)
        } else {
            sendPointer(phase: PointerEvent.hover, fit: fit, point: point)
        }
    }

    func releaseControl() {
        guard pointerIsDown || controlCursor != nil || !controlPoints.isEmpty else { return }
        if pointerIsDown, let model {
            let fit = drawingRect(for: model)
            let point = controlCursor ?? .zero
            sendPointer(phase: PointerEvent.ended, fit: fit, point: point)
        }
        pointerIsDown = false
        controlPoints.removeAll()
        scrollCentroid = nil
        controlCursor = nil
        setNeedsDisplay()
    }

    private func sendPointer(phase: UInt8, fit: CGRect, point: CGPoint, dx: CGFloat = 0, dy: CGFloat = 0) {
        let x = min(1, max(0, (point.x - fit.minX) / fit.width))
        let y = min(1, max(0, (point.y - fit.minY) / fit.height))
        model?.sendPointer(phase: phase, x: x, y: y, dx: dx, dy: dy)
    }

    private func append(_ touches: Set<UITouch>, event: UIEvent?, phase: StrokePhase) {
        guard let model, model.settings.isDrawingEnabled else { return }
        let fit = drawingRect(for: model)
        guard fit.width > 1, fit.height > 1 else { return }
        for touch in touches {
            switch model.settings.inputMode {
            case .pen, .penAndHand:
                guard touch.type == .pencil else { continue }
            case .hand:
                guard touch.type == .direct || touch.type == .pencil else { continue }
            }
            let id = ObjectIdentifier(touch)
            let location = touch.location(in: self)
            if model.settings.selectedTool == .eraser {
                eraserCursor = location
            }
            if phase == .began {
                guard fit.contains(location) else { continue }
                activeTouches.insert(id)
            }
            guard activeTouches.contains(id) else { continue }
            if phase == .ended {
                activeTouches.remove(id)
                if activeTouches.isEmpty, !isHovering {
                    eraserCursor = nil
                }
            }
            let isEraser = model.settings.selectedTool == .eraser
            if isStraightened, !isEraser {
                if phase == .ended {
                    activeTouches.remove(id)
                    cancelHold()
                    isStraightened = false
                } else if let start = straightenStart {
                    currentPoint = location
                    model.straightenLastStroke(
                        from: Self.normalize(start, fit: fit),
                        to: Self.normalize(location, fit: fit),
                        thin: false
                    )
                }
                continue
            }
            let samples = event?.coalescedTouches(for: touch) ?? [touch]
            for (index, sample) in samples.enumerated() {
                let point = sample.location(in: self)
                guard fit.contains(point) else { continue }
                let samplePhase: StrokePhase
                if phase == .began, index == 0 {
                    samplePhase = .began
                } else if phase == .ended, index == samples.count - 1 {
                    samplePhase = .ended
                } else {
                    samplePhase = .moved
                }
                model.addStroke(styledSample(at: point, fit: fit, phase: samplePhase))
            }
            trackStraighten(location: location, phase: phase, isEraser: isEraser, fit: fit)
        }
        if model.settings.selectedTool == .eraser {
            setNeedsDisplay()
        }
    }

    private func trackStraighten(location: CGPoint, phase: StrokePhase, isEraser: Bool, fit: CGRect) {
        if isEraser {
            cancelHold()
            isStraightened = false
            return
        }
        switch phase {
        case .began:
            cancelHold()
            isStraightened = false
            straightenStart = location
            lastGesturePoint = location
            currentPoint = location
            scheduleHold()
        case .moved:
            currentPoint = location
            if let last = lastGesturePoint, hypot(location.x - last.x, location.y - last.y) >= 4 {
                lastGesturePoint = location
                scheduleHold()
            }
        case .ended:
            cancelHold()
            isStraightened = false
            straightenStart = nil
        }
    }

    private func scheduleHold() {
        cancelHold()
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.snapStraight()
        }
        holdTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func snapStraight() {
        guard let model, !isStraightened, model.settings.selectedTool != .eraser else { return }
        guard let start = straightenStart, let end = currentPoint else { return }
        guard hypot(end.x - start.x, end.y - start.y) >= 20 else { return }
        let fit = drawingRect(for: model)
        isStraightened = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.straightenLastStroke(
            from: Self.normalize(start, fit: fit),
            to: Self.normalize(end, fit: fit),
            thin: true
        )
    }

    private func beginBoxEdit(_ touch: UITouch, model: MacLinkModel) {
        let point = touch.location(in: self)
        let fit = drawingRect(for: model)
        if let id = selectedBoxID, let box = model.boxes.first(where: { $0.id == id }) {
            let rect = viewRect(box, fit: fit)
            for corner in BoxCorner.allCases where hypot(cornerPoint(corner, rect: rect).x - point.x, cornerPoint(corner, rect: rect).y - point.y) <= 22 {
                editTouch = ObjectIdentifier(touch)
                edit = .resizing(id: id, corner: corner, origin: rect, start: point)
                previewRect = rect
                return
            }
        }
        if let box = model.boxes.reversed().first(where: { viewRect($0, fit: fit).contains(point) }) {
            selectedBoxID = box.id
            editTouch = ObjectIdentifier(touch)
            edit = .moving(id: box.id, origin: viewRect(box, fit: fit), start: point)
            previewRect = viewRect(box, fit: fit)
            showTrash = true
        } else {
            selectedBoxID = nil
        }
        setNeedsDisplay()
    }

    private func updateBoxEdit(_ touches: Set<UITouch>) -> Bool {
        guard let edit, let editTouch, let touch = touches.first(where: { ObjectIdentifier($0) == editTouch }) else {
            return self.edit != nil
        }
        let point = touch.location(in: self)
        switch edit {
        case .placing(let start):
            previewRect = CGRect(x: start.x, y: start.y, width: point.x - start.x, height: point.y - start.y).standardized
        case .moving(_, let origin, let start):
            var next = origin
            next.origin.x = origin.minX + (point.x - start.x)
            next.origin.y = origin.minY + (point.y - start.y)
            previewRect = next
            showTrash = true
            overTrash = trashFrame.contains(point)
        case .resizing(_, let corner, let origin, let start):
            let translation = CGSize(width: point.x - start.x, height: point.y - start.y)
            previewRect = resized(origin, corner: corner, translation: translation)
        }
        setNeedsDisplay()
        return true
    }

    private func finishBoxEdit(_ touches: Set<UITouch>, commit: Bool) -> Bool {
        guard let edit else { return false }
        if let editTouch, !touches.contains(where: { ObjectIdentifier($0) == editTouch }) {
            return true
        }
        defer { resetEdit() }
        guard commit, let model else { return true }
        let fit = drawingRect(for: model)
        guard fit.width > 1, fit.height > 1 else {
            if model.isPlacingWhiteRect { model.finishBoxPlacement() }
            return true
        }
        switch edit {
        case .placing:
            if model.isPlacingWhiteRect { model.finishBoxPlacement() }
            guard let rect = previewRect?.standardized, rect.width >= 24, rect.height >= 24 else { return true }
            let box = LinkBox(
                id: UUID(),
                x: Double((rect.minX - fit.minX) / fit.width),
                y: Double((rect.minY - fit.minY) / fit.height),
                width: Double(rect.width / fit.width),
                height: Double(rect.height / fit.height)
            )
            var boxes = model.boxes
            boxes.append(box)
            selectedBoxID = box.id
            model.setBoxes(boxes, send: true)
        case .moving(let id, _, _):
            var boxes = model.boxes
            if overTrash {
                boxes.removeAll { $0.id == id }
                if selectedBoxID == id { selectedBoxID = nil }
            } else if let rect = previewRect, let index = boxes.firstIndex(where: { $0.id == id }) {
                boxes[index].x = Double((rect.minX - fit.minX) / fit.width)
                boxes[index].y = Double((rect.minY - fit.minY) / fit.height)
                boxes[index].width = Double(rect.width / fit.width)
                boxes[index].height = Double(rect.height / fit.height)
            }
            model.setBoxes(boxes, send: true)
        case .resizing(let id, _, _, _):
            guard let rect = previewRect else { return true }
            var boxes = model.boxes
            guard let index = boxes.firstIndex(where: { $0.id == id }) else { return true }
            boxes[index].x = Double((rect.minX - fit.minX) / fit.width)
            boxes[index].y = Double((rect.minY - fit.minY) / fit.height)
            boxes[index].width = Double(rect.width / fit.width)
            boxes[index].height = Double(rect.height / fit.height)
            model.setBoxes(boxes, send: true)
        }
        return true
    }

    private func resetEdit() {
        edit = nil
        editTouch = nil
        previewRect = nil
        showTrash = false
        overTrash = false
        setNeedsDisplay()
    }

    private func drawBoxes(_ model: MacLinkModel, fit: CGRect) {
        let editing = !model.settings.isDrawingEnabled && !model.isPlacingWhiteRect
        for box in model.boxes {
            var rect = viewRect(box, fit: fit)
            if let previewRect, case .moving(let id, _, _) = edit, id == box.id {
                rect = previewRect
            }
            if let previewRect, case .resizing(let id, _, _, _) = edit, id == box.id {
                rect = previewRect
            }
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            UIColor.white.setFill()
            path.fill()
            guard editing, selectedBoxID == box.id else { continue }
            UIColor.systemBlue.setStroke()
            path.lineWidth = 2
            path.stroke()
            for corner in BoxCorner.allCases {
                let center = cornerPoint(corner, rect: rect)
                let handle = UIBezierPath(ovalIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
                UIColor.white.setFill()
                handle.fill()
                UIColor.systemBlue.setStroke()
                handle.lineWidth = 2
                handle.stroke()
            }
        }
    }

    private func drawPlacementDraft() {
        guard case .placing = edit, let rect = previewRect, rect.width > 1, rect.height > 1 else { return }
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
        UIColor.white.withAlphaComponent(0.92).setFill()
        path.fill()
        UIColor.systemBlue.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawTrash() {
        guard showTrash else { return }
        let rect = trashFrame
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        (overTrash ? UIColor.systemRed : UIColor.secondarySystemBackground).setFill()
        path.fill()
        let title = "삭제" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: overTrash ? UIColor.white : UIColor.label
        ]
        let size = title.size(withAttributes: attributes)
        title.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private var trashFrame: CGRect {
        CGRect(x: bounds.midX - 36, y: bounds.maxY - 72, width: 72, height: 40)
    }

    private func viewRect(_ box: LinkBox, fit: CGRect) -> CGRect {
        CGRect(
            x: fit.minX + box.x * fit.width,
            y: fit.minY + box.y * fit.height,
            width: box.width * fit.width,
            height: box.height * fit.height
        )
    }

    private func cornerPoint(_ corner: BoxCorner, rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeading: return CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeading: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomTrailing: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func resized(_ original: CGRect, corner: BoxCorner, translation: CGSize) -> CGRect {
        let minSide: CGFloat = 40
        var rect = original
        switch corner {
        case .topLeading:
            rect.origin.x = min(original.maxX - minSide, original.minX + translation.width)
            rect.origin.y = min(original.maxY - minSide, original.minY + translation.height)
            rect.size.width = max(minSide, original.maxX - rect.origin.x)
            rect.size.height = max(minSide, original.maxY - rect.origin.y)
        case .topTrailing:
            rect.origin.y = min(original.maxY - minSide, original.minY + translation.height)
            rect.size.width = max(minSide, original.width + translation.width)
            rect.size.height = max(minSide, original.maxY - rect.origin.y)
        case .bottomLeading:
            rect.origin.x = min(original.maxX - minSide, original.minX + translation.width)
            rect.size.width = max(minSide, original.maxX - rect.origin.x)
            rect.size.height = max(minSide, original.height + translation.height)
        case .bottomTrailing:
            rect.size.width = max(minSide, original.width + translation.width)
            rect.size.height = max(minSide, original.height + translation.height)
        }
        return rect
    }

    func clearInkSelection() {
        guard inkGesture != nil || marqueeRect != nil || moveDelta != .zero || !selectedStrokeIndices.isEmpty else { return }
        inkGesture = nil
        selectionTouch = nil
        marqueeRect = nil
        moveDelta = .zero
        selectedStrokeIndices = []
        setNeedsDisplay()
    }

    private func beginInkSelection(_ touches: Set<UITouch>) {
        guard inkGesture == nil, let touch = touches.first, let model else { return }
        let point = touch.location(in: self)
        selectionTouch = ObjectIdentifier(touch)
        let fit = drawingRect(for: model)
        if let bounds = selectionBounds(fit: fit), bounds.contains(point) {
            inkGesture = .moving(start: point)
            moveDelta = .zero
        } else {
            selectedStrokeIndices = []
            inkGesture = .marquee(start: point)
            marqueeRect = CGRect(origin: point, size: .zero)
        }
        setNeedsDisplay()
    }

    private func updateInkSelection(_ touches: Set<UITouch>) {
        guard let inkGesture, let selectionTouch,
              let touch = touches.first(where: { ObjectIdentifier($0) == selectionTouch }) else { return }
        let point = touch.location(in: self)
        switch inkGesture {
        case .marquee(let start):
            marqueeRect = CGRect(x: start.x, y: start.y, width: point.x - start.x, height: point.y - start.y).standardized
        case .moving(let start):
            moveDelta = CGSize(width: point.x - start.x, height: point.y - start.y)
        }
        setNeedsDisplay()
    }

    private func finishInkSelection(_ touches: Set<UITouch>, commit: Bool) {
        guard inkGesture != nil else { return }
        if let selectionTouch, !touches.contains(where: { ObjectIdentifier($0) == selectionTouch }) {
            return
        }
        let gesture = inkGesture
        let delta = moveDelta
        let marquee = marqueeRect
        inkGesture = nil
        selectionTouch = nil
        marqueeRect = nil
        moveDelta = .zero
        defer { setNeedsDisplay() }
        guard commit, let model, let gesture else {
            return
        }
        let fit = drawingRect(for: model)
        guard fit.width > 1, fit.height > 1 else { return }
        switch gesture {
        case .marquee(let start):
            guard let marquee else {
                selectedStrokeIndices = []
                return
            }
            if marquee.width < 8, marquee.height < 8 {
                let point = Self.normalize(start, fit: fit)
                let tap = CGRect(x: point.x - 0.01, y: point.y - 0.01, width: 0.02, height: 0.02)
                selectedStrokeIndices = IndexSet(
                    model.ink.strokes.indices.filter { model.ink.strokes[$0].intersects(tap) }.suffix(1)
                )
            } else {
                let normalized = CGRect(
                    x: (marquee.minX - fit.minX) / fit.width,
                    y: (marquee.minY - fit.minY) / fit.height,
                    width: marquee.width / fit.width,
                    height: marquee.height / fit.height
                )
                selectedStrokeIndices = IndexSet(
                    model.ink.strokes.indices.filter { model.ink.strokes[$0].intersects(normalized) }
                )
            }
        case .moving:
            guard hypot(delta.width, delta.height) > 1 else { return }
            let dx = delta.width / fit.width
            let dy = delta.height / fit.height
            var strokes = model.ink.strokes
            var moved = false
            for index in selectedStrokeIndices where strokes.indices.contains(index) {
                strokes[index].points = strokes[index].points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                moved = true
            }
            if moved {
                model.replaceInk(strokes)
            }
        }
    }

    private func shiftedStrokes(_ strokes: [LinkStroke], fit: CGRect) -> [LinkStroke] {
        guard fit.width > 1, fit.height > 1 else { return strokes }
        let dx = moveDelta.width / fit.width
        let dy = moveDelta.height / fit.height
        return strokes.enumerated().map { index, stroke in
            guard selectedStrokeIndices.contains(index) else { return stroke }
            var moved = stroke
            moved.points = stroke.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            return moved
        }
    }

    private func selectionBounds(fit: CGRect) -> CGRect? {
        guard let model, !selectedStrokeIndices.isEmpty else { return nil }
        var rect: CGRect?
        for index in selectedStrokeIndices {
            guard model.ink.strokes.indices.contains(index) else { continue }
            let stroke = model.ink.strokes[index]
            let pad = max(8, fit.height * stroke.widthFraction / 2)
            for point in stroke.points {
                let viewPoint = Self.map(point, fit: fit)
                let dot = CGRect(x: viewPoint.x - pad, y: viewPoint.y - pad, width: pad * 2, height: pad * 2)
                rect = rect?.union(dot) ?? dot
            }
        }
        return rect?.insetBy(dx: -8, dy: -8)
    }

    private func drawInkSelection(fit: CGRect) {
        guard model?.settings.selectedTool == .selection else { return }
        if let marqueeRect, marqueeRect.width > 1, marqueeRect.height > 1 {
            let path = UIBezierPath(rect: marqueeRect)
            UIColor.systemBlue.withAlphaComponent(0.15).setFill()
            path.fill()
            path.lineWidth = 1.5
            path.setLineDash([5, 4], count: 2, phase: 0)
            UIColor.systemBlue.setStroke()
            path.stroke()
        }
        if var bounds = selectionBounds(fit: fit) {
            bounds.origin.x += moveDelta.width
            bounds.origin.y += moveDelta.height
            let path = UIBezierPath(roundedRect: bounds, cornerRadius: 6)
            path.lineWidth = 1.5
            path.setLineDash([5, 4], count: 2, phase: 0)
            UIColor.systemBlue.setStroke()
            path.stroke()
        }
    }

    private func drawingRect(for model: MacLinkModel) -> CGRect {
        guard let image = model.image else { return bounds }
        return Self.aspectFit(image.size, in: bounds)
    }

    private func styledSample(at point: CGPoint, fit: CGRect, phase: StrokePhase) -> StrokeSample {
        let settings = model?.settings ?? ToolSettings()
        let kind = settings.selectedTool
        let fraction = Double(settings.width(for: kind) / max(fit.height, 1))
        let hex: String
        let alpha: Double
        let isEraser: Bool
        switch kind {
        case .blackPen:
            hex = "#000000"
            alpha = 1
            isEraser = false
        case .colorPen:
            hex = settings.colorPenColorHex
            alpha = 1
            isEraser = false
        case .highlighter:
            hex = settings.highlighterColorHex
            alpha = 0.45
            isEraser = false
        case .eraser:
            hex = "#000000"
            alpha = 1
            isEraser = true
        case .selection:
            hex = "#000000"
            alpha = 1
            isEraser = false
        }
        return StrokeSample(
            x: Double((point.x - fit.minX) / fit.width),
            y: Double((point.y - fit.minY) / fit.height),
            phase: phase,
            colorHex: hex,
            alpha: alpha,
            widthFraction: fraction,
            isEraser: isEraser
        )
    }

    private func renderInk(_ strokes: [LinkStroke], fit: CGRect) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                strokePath(stroke, fit: fit, in: cg, clear: stroke.isEraser)
            }
        }
    }

    private func strokePath(_ stroke: LinkStroke, fit: CGRect, in context: CGContext, clear: Bool) {
        guard let first = stroke.points.first else { return }
        context.saveGState()
        if clear {
            context.setBlendMode(.destinationOut)
        }
        let color = clear
            ? UIColor.black
            : UIColor(Color(hex: stroke.colorHex)).withAlphaComponent(stroke.alpha)
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        let width = max(1, fit.height * stroke.widthFraction)
        context.setLineWidth(width)
        let start = Self.map(first, fit: fit)
        if stroke.points.count == 1 {
            context.fillEllipse(in: CGRect(x: start.x - width / 2, y: start.y - width / 2, width: width, height: width))
        } else {
            context.beginPath()
            context.move(to: start)
            for point in stroke.points.dropFirst() {
                context.addLine(to: Self.map(point, fit: fit))
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func aspectFit(_ imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func normalize(_ point: CGPoint, fit: CGRect) -> CGPoint {
        CGPoint(x: (point.x - fit.minX) / fit.width, y: (point.y - fit.minY) / fit.height)
    }

    private static func map(_ point: CGPoint, fit: CGRect) -> CGPoint {
        CGPoint(x: fit.minX + point.x * fit.width, y: fit.minY + point.y * fit.height)
    }
}
