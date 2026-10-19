import SwiftUI
import PencilKit

enum DrawingToolKind: String, CaseIterable, Identifiable, Codable {
    case blackPen
    case colorPen
    case highlighter
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blackPen: return "검정"
        case .colorPen: return "컬러"
        case .highlighter: return "형광"
        case .eraser: return "지우개"
        }
    }

    var systemImage: String {
        switch self {
        case .blackPen: return "pencil.tip"
        case .colorPen: return "paintbrush.pointed"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        }
    }
}

struct ToolSettings: Codable, Equatable {
    var selectedTool: DrawingToolKind = .blackPen
    /// 지우개 전환 전에 쓰던 잉크 도구 (검정/컬러/형광)
    var lastInkTool: DrawingToolKind = .blackPen
    var isDrawingEnabled: Bool = true
    /// true면 손가락+펜, false면 Apple Pencil만 필기
    var allowsFingerDrawing: Bool = true

    var blackPenWidth: CGFloat = 5
    var colorPenWidth: CGFloat = 5
    var colorPenColorHex: String = "#E53935"
    var highlighterWidth: CGFloat = 18
    var highlighterColorHex: String = "#FFEB3B"
    var eraserWidth: CGFloat = 30

    /// UIColor.black는 다크모드에서 동적 색으로 뒤집힐 수 있어 고정 RGB를 사용한다.
    private static let solidBlack = UIColor(red: 0, green: 0, blue: 0, alpha: 1)

    enum CodingKeys: String, CodingKey {
        case selectedTool, lastInkTool, isDrawingEnabled, allowsFingerDrawing
        case blackPenWidth, colorPenWidth, colorPenColorHex
        case highlighterWidth, highlighterColorHex, eraserWidth
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedTool = try c.decodeIfPresent(DrawingToolKind.self, forKey: .selectedTool) ?? .blackPen
        isDrawingEnabled = try c.decodeIfPresent(Bool.self, forKey: .isDrawingEnabled) ?? true
        allowsFingerDrawing = try c.decodeIfPresent(Bool.self, forKey: .allowsFingerDrawing) ?? true
        blackPenWidth = try c.decodeIfPresent(CGFloat.self, forKey: .blackPenWidth) ?? 5
        colorPenWidth = try c.decodeIfPresent(CGFloat.self, forKey: .colorPenWidth) ?? 5
        colorPenColorHex = try c.decodeIfPresent(String.self, forKey: .colorPenColorHex) ?? "#E53935"
        highlighterWidth = try c.decodeIfPresent(CGFloat.self, forKey: .highlighterWidth) ?? 18
        highlighterColorHex = try c.decodeIfPresent(String.self, forKey: .highlighterColorHex) ?? "#FFEB3B"
        eraserWidth = try c.decodeIfPresent(CGFloat.self, forKey: .eraserWidth) ?? 30

        if let savedLast = try c.decodeIfPresent(DrawingToolKind.self, forKey: .lastInkTool),
           savedLast != .eraser {
            lastInkTool = savedLast
        } else if selectedTool != .eraser {
            lastInkTool = selectedTool
        } else {
            lastInkTool = .blackPen
        }
    }

    var isEraserSelected: Bool { selectedTool == .eraser }

    /// 빠른 전환 시 돌아갈 잉크 도구 (지우개가 저장돼 있으면 검정으로 보정)
    var resolvedLastInkTool: DrawingToolKind {
        lastInkTool == .eraser ? .blackPen : lastInkTool
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
        }
    }

    mutating func selectTool(_ kind: DrawingToolKind) {
        if kind != .eraser {
            lastInkTool = kind
        }
        selectedTool = kind
    }

    /// 지우개 ↔ 직전 펜/형광 전환
    mutating func toggleEraserWithLastInk() {
        if selectedTool == .eraser {
            selectedTool = resolvedLastInkTool
        } else {
            lastInkTool = selectedTool
            selectedTool = .eraser
        }
    }

    mutating func setWidth(_ width: CGFloat, for kind: DrawingToolKind) {
        switch kind {
        case .blackPen: blackPenWidth = width
        case .colorPen: colorPenWidth = width
        case .highlighter: highlighterWidth = width
        case .eraser: eraserWidth = width
        }
    }

    func width(for kind: DrawingToolKind) -> CGFloat {
        switch kind {
        case .blackPen: return blackPenWidth
        case .colorPen: return colorPenWidth
        case .highlighter: return highlighterWidth
        case .eraser: return eraserWidth
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
