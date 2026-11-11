import SwiftUI
import PencilKit

enum DrawingToolKind: String, CaseIterable, Identifiable, Codable {
    case blackPen
    case colorPen
    case highlighter
    case eraser
    case selection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blackPen: return "검정"
        case .colorPen: return "컬러"
        case .highlighter: return "형광"
        case .eraser: return "지우개"
        case .selection: return "선택"
        }
    }

    var systemImage: String {
        switch self {
        case .blackPen: return "pencil.tip"
        case .colorPen: return "paintbrush.pointed"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .selection: return "lasso"
        }
    }
}

/// 필기·화면 조작에 쓰는 입력.
enum DrawingInputMode: String, CaseIterable, Identifiable, Codable {
    case pen
    case penAndHand
    case hand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return "펜"
        case .penAndHand: return "손+펜"
        case .hand: return "손"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "applepencil"
        case .penAndHand: return "hand.point.up.left"
        case .hand: return "hand.draw"
        }
    }

    var hint: String {
        switch self {
        case .pen: return "펜으로 필기 · 화면 조작은 마우스 버튼"
        case .penAndHand: return "펜으로 필기 · 손으로 화면 조작"
        case .hand: return "손으로 필기 · 화면 조작은 마우스 버튼"
        }
    }

    /// PencilKit에서 손가락 필기를 받을지.
    var allowsFingerDrawing: Bool { self == .hand }

    /// 메인 캔버스에서 한 손가락 스크롤을 쓸지. 손 필기일 땐 두 손가락만.
    var usesOneFingerCanvasScroll: Bool { self != .hand }
}

struct ToolSettings: Codable, Equatable {
    var selectedTool: DrawingToolKind = .blackPen
    /// 지우개 전환 전에 쓰던 잉크 도구 (검정/컬러/형광)
    var lastInkTool: DrawingToolKind = .blackPen
    var isDrawingEnabled: Bool = true
    var inputMode: DrawingInputMode = .pen

    var blackPenWidth: CGFloat = 5
    var colorPenWidth: CGFloat = 5
    var colorPenColorHex: String = "#E53935"
    var highlighterWidth: CGFloat = 18
    var highlighterColorHex: String = "#FFEB3B"
    var eraserWidth: CGFloat = 30

    /// UIColor.black는 다크모드에서 동적 색으로 뒤집힐 수 있어 고정 RGB를 사용한다.
    private static let solidBlack = UIColor(red: 0, green: 0, blue: 0, alpha: 1)

    enum CodingKeys: String, CodingKey {
        case selectedTool, lastInkTool, isDrawingEnabled, inputMode, allowsFingerDrawing
        case blackPenWidth, colorPenWidth, colorPenColorHex
        case highlighterWidth, highlighterColorHex, eraserWidth
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedTool = try c.decodeIfPresent(DrawingToolKind.self, forKey: .selectedTool) ?? .blackPen
        isDrawingEnabled = try c.decodeIfPresent(Bool.self, forKey: .isDrawingEnabled) ?? true
        if let mode = try c.decodeIfPresent(DrawingInputMode.self, forKey: .inputMode) {
            inputMode = mode
        } else if let finger = try c.decodeIfPresent(Bool.self, forKey: .allowsFingerDrawing) {
            inputMode = finger ? .hand : .pen
        } else {
            inputMode = .pen
        }
        blackPenWidth = try c.decodeIfPresent(CGFloat.self, forKey: .blackPenWidth) ?? 5
        colorPenWidth = try c.decodeIfPresent(CGFloat.self, forKey: .colorPenWidth) ?? 5
        colorPenColorHex = try c.decodeIfPresent(String.self, forKey: .colorPenColorHex) ?? "#E53935"
        highlighterWidth = try c.decodeIfPresent(CGFloat.self, forKey: .highlighterWidth) ?? 18
        highlighterColorHex = try c.decodeIfPresent(String.self, forKey: .highlighterColorHex) ?? "#FFEB3B"
        eraserWidth = try c.decodeIfPresent(CGFloat.self, forKey: .eraserWidth) ?? 30

        if let savedLast = try c.decodeIfPresent(DrawingToolKind.self, forKey: .lastInkTool),
           savedLast != .eraser, savedLast != .selection {
            lastInkTool = savedLast
        } else if selectedTool != .eraser, selectedTool != .selection {
            lastInkTool = selectedTool
        } else {
            lastInkTool = .blackPen
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(selectedTool, forKey: .selectedTool)
        try c.encode(lastInkTool, forKey: .lastInkTool)
        try c.encode(isDrawingEnabled, forKey: .isDrawingEnabled)
        try c.encode(inputMode, forKey: .inputMode)
        try c.encode(blackPenWidth, forKey: .blackPenWidth)
        try c.encode(colorPenWidth, forKey: .colorPenWidth)
        try c.encode(colorPenColorHex, forKey: .colorPenColorHex)
        try c.encode(highlighterWidth, forKey: .highlighterWidth)
        try c.encode(highlighterColorHex, forKey: .highlighterColorHex)
        try c.encode(eraserWidth, forKey: .eraserWidth)
    }

    var allowsFingerDrawing: Bool { inputMode.allowsFingerDrawing }

    var isEraserSelected: Bool { selectedTool == .eraser }

    /// 빠른 전환 시 돌아갈 잉크 도구. 지우개·선택은 잉크가 아니라 검정으로 보정한다.
    var resolvedLastInkTool: DrawingToolKind {
        switch lastInkTool {
        case .eraser, .selection: return .blackPen
        default: return lastInkTool
        }
    }

    func makeTool(for kind: DrawingToolKind) -> PKTool {
        switch kind {
        case .blackPen:
            return PKInkingTool(.pen, color: Self.solidBlack, width: blackPenWidth)
        case .colorPen:
            return PKInkingTool(.pen, color: UIColor(Color(hex: colorPenColorHex)), width: colorPenWidth)
        case .highlighter:
            let color = UIColor(Color(hex: highlighterColorHex)).withAlphaComponent(0.5)
            return PKInkingTool(.marker, color: color, width: highlighterWidth)
        case .eraser:
            return PKEraserTool(.bitmap, width: eraserWidth)
        case .selection:
            return PKLassoTool()
        }
    }

    mutating func selectTool(_ kind: DrawingToolKind) {
        if kind != .eraser, kind != .selection {
            lastInkTool = kind
        }
        selectedTool = kind
    }

    /// 지우개 ↔ 직전 펜/형광 전환
    mutating func toggleEraserWithLastInk() {
        if selectedTool == .eraser {
            selectedTool = resolvedLastInkTool
        } else if selectedTool != .selection {
            lastInkTool = selectedTool
            selectedTool = .eraser
        } else {
            selectedTool = .eraser
        }
    }

    mutating func setWidth(_ width: CGFloat, for kind: DrawingToolKind) {
        switch kind {
        case .blackPen: blackPenWidth = width
        case .colorPen: colorPenWidth = width
        case .highlighter: highlighterWidth = width
        case .eraser: eraserWidth = width
        case .selection: break
        }
    }

    func width(for kind: DrawingToolKind) -> CGFloat {
        switch kind {
        case .blackPen: return blackPenWidth
        case .colorPen: return colorPenWidth
        case .highlighter: return highlighterWidth
        case .eraser: return eraserWidth
        case .selection: return 1
        }
    }

}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// 다크모드에 영향받지 않는 순수 검정
    static let solidBlack = Color(red: 0, green: 0, blue: 0)

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#000000"
        }
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}
