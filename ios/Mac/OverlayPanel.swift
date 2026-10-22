import AppKit

/// 다른 앱 위에 올라가는 투명 창. 클릭은 아래로 통과하고, 화면 캡처에는 포함되지 않는다.
final class OverlayPanel {
    private let panel: NSPanel
    private let canvas = OverlayCanvasView(frame: .zero)

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none
        canvas.autoresizingMask = [.width, .height]
        panel.contentView = canvas
    }

    func showOnMainScreen() {
        guard let screen = NSScreen.main else { return }
        panel.setFrame(screen.frame, display: true)
        canvas.frame = panel.contentView?.bounds ?? screen.frame
        guard contentVisible else { return }
        panel.orderFrontRegardless()
    }

    func add(_ sample: StrokeSample) {
        canvas.add(sample)
    }

    func undo() {
        canvas.undo()
    }

    func redo() {
        canvas.redo()
    }

    func clear() {
        canvas.clear()
    }

    func clearAll() {
        canvas.clearAll()
    }

    func replaceLast(_ stroke: LinkStroke) {
        canvas.replaceLast(stroke)
    }

    func setBoxes(_ boxes: [LinkBox]) {
        canvas.setBoxes(boxes)
    }

    /// 필기와 상자는 유지한 채 창만 접거나 다시 연다.
    func setContentVisible(_ visible: Bool) {
        contentVisible = visible
        if visible {
            showOnMainScreen()
        } else {
            panel.orderOut(nil)
        }
    }

    private var contentVisible = true
}

final class OverlayCanvasView: NSView {
    private var ink = LinkInk()
    private var boxes: [LinkBox] = []
    private var inkContext: CGContext?
    private var inkPixelSize = CGSize.zero

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func add(_ sample: StrokeSample) {
        ink.add(sample)
        needsDisplay = true
    }

    func undo() {
        ink.undo()
        needsDisplay = true
    }

    func redo() {
        ink.redo()
        needsDisplay = true
    }

    func clear() {
        ink.clear()
        needsDisplay = true
    }

    func clearAll() {
        ink.clear()
        boxes = []
        needsDisplay = true
    }

    func replaceLast(_ stroke: LinkStroke) {
        ink.replaceLast(stroke)
        needsDisplay = true
    }

    func setBoxes(_ boxes: [LinkBox]) {
        self.boxes = boxes
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // destinationOut를 창에 직접 쓰면 지운 자리가 뚫린 채로 남아 그 위에 다시 그리지 못한다.
        NSColor.clear.set()
        bounds.fill(using: .copy)

        for box in boxes {
            let rect = CGRect(
                x: box.x * bounds.width,
                y: box.y * bounds.height,
                width: max(1, box.width * bounds.width),
                height: max(1, box.height * bounds.height)
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 3
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        if let image = makeInkImage(), let context = NSGraphicsContext.current?.cgContext {
            // 뒤집힌 뷰에서 CGImage를 그대로 붙이면 위아래가 바뀐다. 상자 좌표와 맞춘다.
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
            context.restoreGState()
        }
    }

    private func makeInkImage() -> CGImage? {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = max(1, Int((bounds.width * scale).rounded()))
        let pixelHeight = max(1, Int((bounds.height * scale).rounded()))
        guard let ctx = bitmapContext(pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale) else { return nil }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in ink.strokes {
            strokePath(stroke, in: ctx, blend: stroke.isEraser ? .destinationOut : .normal)
        }
        return ctx.makeImage()
    }

    private func bitmapContext(pixelWidth: Int, pixelHeight: Int, scale: CGFloat) -> CGContext? {
        let size = CGSize(width: pixelWidth, height: pixelHeight)
        let ctx: CGContext
        if let inkContext, inkPixelSize == size {
            ctx = inkContext
            ctx.restoreGState()
            ctx.saveGState()
        } else {
            guard let created = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            created.saveGState()
            inkContext = created
            inkPixelSize = size
            ctx = created
        }
        ctx.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: scale, y: -scale)
        return ctx
    }

    private func strokePath(_ stroke: LinkStroke, in context: CGContext, blend: CGBlendMode) {
        guard let first = stroke.points.first else { return }
        context.saveGState()
        context.setBlendMode(blend)
        let color = stroke.isEraser
            ? NSColor.black
            : Self.color(hex: stroke.colorHex, alpha: stroke.alpha)
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(max(1, bounds.height * stroke.widthFraction))
        let start = map(first)
        if stroke.points.count == 1 {
            let radius = max(0.5, bounds.height * stroke.widthFraction / 2)
            context.fillEllipse(in: CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2))
        } else {
            context.beginPath()
            context.move(to: start)
            for point in stroke.points.dropFirst() {
                context.addLine(to: map(point))
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private func map(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)
    }

    private static func color(hex: String, alpha: Double) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}
