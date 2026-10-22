import Foundation
import Network

enum LinkService {
    static let type = "_laypen-link._tcp"

    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

enum LinkMessageKind: UInt8 {
    case hello = 1
    case accept = 2
    case reject = 3
    case frame = 4
    case stroke = 5
    case clear = 6
    case undo = 7
    case redo = 8
    case replaceStroke = 9
    case boxes = 10
    case clearAll = 11
    case overlayVisible = 12
}

struct LinkHello: Codable, Equatable {
    var code: String
    var name: String
    var peerID: String
    var token: String
}

struct LinkAccept: Codable, Equatable {
    var macID: String
    var token: String
}

enum StrokePhase: String, Codable {
    case began
    case moved
    case ended
}

struct StrokeSample: Codable, Equatable {
    var x: Double
    var y: Double
    var phase: StrokePhase
    var colorHex: String
    var alpha: Double
    var widthFraction: Double
    var isEraser: Bool
}

struct LinkStroke: Codable, Equatable {
    var points: [CGPoint]
    var colorHex: String
    var alpha: Double
    var widthFraction: Double
    var isEraser: Bool
}

/// 맥과 아이패드가 같은 JSON으로 주고받는 획. CGPoint 인코딩 차이에 기대지 않는다.
struct LinkStrokeWire: Codable, Equatable {
    var xs: [Double]
    var ys: [Double]
    var colorHex: String
    var alpha: Double
    var widthFraction: Double
    var isEraser: Bool

    init(_ stroke: LinkStroke) {
        xs = stroke.points.map { Double($0.x) }
        ys = stroke.points.map { Double($0.y) }
        colorHex = stroke.colorHex
        alpha = stroke.alpha
        widthFraction = stroke.widthFraction
        isEraser = stroke.isEraser
    }

    func stroke() -> LinkStroke {
        let count = min(xs.count, ys.count)
        return LinkStroke(
            points: (0..<count).map { CGPoint(x: xs[$0], y: ys[$0]) },
            colorHex: colorHex,
            alpha: alpha,
            widthFraction: widthFraction,
            isEraser: isEraser
        )
    }
}

struct LinkBox: Codable, Equatable, Identifiable {
    var id: UUID
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct LinkInk: Equatable {
    private(set) var strokes: [LinkStroke] = []
    private var undoStack: [[LinkStroke]] = []
    private var redoStack: [[LinkStroke]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func add(_ sample: StrokeSample) {
        let point = CGPoint(x: min(1, max(0, sample.x)), y: min(1, max(0, sample.y)))
        switch sample.phase {
        case .began:
            pushUndo()
            redoStack.removeAll()
            strokes.append(LinkStroke(
                points: [point],
                colorHex: sample.colorHex,
                alpha: sample.alpha,
                widthFraction: sample.widthFraction,
                isEraser: sample.isEraser
            ))
        case .moved, .ended:
            guard !strokes.isEmpty else { return }
            strokes[strokes.count - 1].points.append(point)
        }
    }

    mutating func replaceLast(_ stroke: LinkStroke) {
        guard !strokes.isEmpty else { return }
        strokes[strokes.count - 1] = stroke
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }

    mutating func clear() {
        guard !strokes.isEmpty else { return }
        pushUndo()
        redoStack.removeAll()
        strokes = []
    }

    private mutating func pushUndo() {
        undoStack.append(strokes)
        if undoStack.count > 80 {
            undoStack.removeFirst()
        }
    }
}

enum LinkStrokeStyle {
    /// 캡처된 화면 높이 대비 선 굵기. 맥 오버레이와 아이패드가 같은 비율을 쓴다.
    static let widthFraction: CGFloat = 0.004
}

enum LinkCodec {
    static let headerSize = 5
    static let maxPayload = 8_000_000

    static func encode(kind: LinkMessageKind, payload: Data) -> Data {
        var data = Data(capacity: headerSize + payload.count)
        data.append(kind.rawValue)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }
}

struct LinkFramer {
    private var buffer = Data()

    mutating func append(_ chunk: Data) -> [(LinkMessageKind, Data)] {
        buffer.append(chunk)
        var messages: [(LinkMessageKind, Data)] = []
        while buffer.count >= LinkCodec.headerSize {
            guard let kind = LinkMessageKind(rawValue: buffer[buffer.startIndex]) else {
                buffer.removeAll(keepingCapacity: true)
                break
            }
            let lengthIndex = buffer.index(buffer.startIndex, offsetBy: 1)
            let length = Int(Self.uint32(buffer, at: lengthIndex))
            guard length <= LinkCodec.maxPayload else {
                buffer.removeAll(keepingCapacity: true)
                break
            }
            let total = LinkCodec.headerSize + length
            guard buffer.count >= total else { break }
            let payloadStart = buffer.index(buffer.startIndex, offsetBy: LinkCodec.headerSize)
            let payloadEnd = buffer.index(payloadStart, offsetBy: length)
            let payload = Data(buffer[payloadStart..<payloadEnd])
            buffer.removeFirst(total)
            messages.append((kind, payload))
        }
        return messages
    }

    private static func uint32(_ data: Data, at index: Data.Index) -> UInt32 {
        let b0 = UInt32(data[index])
        let b1 = UInt32(data[data.index(index, offsetBy: 1)])
        let b2 = UInt32(data[data.index(index, offsetBy: 2)])
        let b3 = UInt32(data[data.index(index, offsetBy: 3)])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }
}
