import Foundation
import Network
import UIKit

struct NearbyMac: Identifiable, Hashable {
    var name: String
    var endpoint: NWEndpoint
    var macID: String?
    var id: NWEndpoint { endpoint }

    var isTrusted: Bool {
        !savedToken.isEmpty
    }

    var savedToken: String {
        if let macID, let token = LinkTrustStore.token(for: macID), !token.isEmpty {
            return token
        }
        return LinkTrustStore.token(named: name) ?? ""
    }
}

final class MacLinkModel: ObservableObject {
    @Published private(set) var nearby: [NearbyMac] = []
    @Published private(set) var status = "주변의 맥을 찾는 중"
    @Published private(set) var isConnected = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var code = ""
    /// 저장된 연결이 거절되면 코드 칸을 다시 연다.
    @Published var asksForCode = false
    @Published var selectedID: NWEndpoint?
    @Published var settings = ToolSettings()
    @Published var showsMacScreen = true
    /// 맥 화면 위 필기와 상자를 보여 준다. 끄면 데이터는 남기고 오버레이만 접는다.
    @Published var showsMacInk = true
    @Published var showClearConfirm = false
    @Published var showClearInkConfirm = false
    @Published var isPlacingWhiteRect = false
    /// 켜면 아이패드 터치가 맥의 클릭·드래그·스크롤이 된다.
    @Published var controlsMac = false

    private(set) var image: UIImage?
    private(set) var ink = LinkInk()
    private(set) var boxes: [LinkBox] = []
    var onCanvasChange: (() -> Void)?

    private var pendingPeerName: String?
    private var browser: NWBrowser?
    private var channel: LinkChannel?
    private let queue = DispatchQueue(label: "laypen.link.browser")
    private let frameQueue = DispatchQueue(label: "laypen.link.frames")
    private let frameDecoder = LinkFrameDecoder()
    private var pendingFrames: [Data] = []
    private var isDecodingFrame = false

    init(settings: ToolSettings = ToolSettings()) {
        self.settings = settings
    }

    var selectedMacIsTrusted: Bool {
        selectedMac?.isTrusted == true
    }

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: LinkService.type, domain: nil),
            using: LinkService.parameters()
        )
        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self, !self.isConnected else { return }
                if case .waiting = state {
                    self.status = "로컬 네트워크 권한을 허용해야 주변 맥을 찾을 수 있습니다."
                } else if case .failed(let error) = state {
                    self.status = "맥을 찾지 못했습니다. \(error.localizedDescription)"
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> NearbyMac? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                var macID: String?
                if case let .bonjour(txt) = result.metadata {
                    macID = txt.dictionary["id"] ?? txt["id"]
                }
                if macID == nil {
                    macID = LinkTrustStore.remoteID(named: name)
                }
                return NearbyMac(name: name, endpoint: result.endpoint, macID: macID)
            }.sorted { $0.name < $1.name }
            let resolved = Self.attachSoleTrust(found)
            DispatchQueue.main.async {
                self?.apply(resolved)
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func setCode(_ raw: String) {
        code = String(raw.filter(\.isNumber).prefix(4))
    }

    func connect() {
        guard channel == nil, let mac = selectedMac else { return }
        pendingPeerName = mac.name
        let saved = mac.savedToken
        let typingCode = asksForCode || saved.isEmpty
        if typingCode, code.count != 4 { return }
        let connection = NWConnection(to: mac.endpoint, using: LinkService.parameters())
        let channel = LinkChannel(connection)
        channel.onMessage = { [weak self] kind, payload in
            self?.handle(kind, payload)
        }
        channel.onEnded = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.channel === channel else { return }
                self.handleDisconnect(message: "연결이 끊어졌습니다.")
            }
        }
        self.channel = channel
        status = "연결하는 중"
        channel.start()
        let hello = LinkHello(
            code: typingCode ? code : "",
            name: UIDevice.current.name,
            peerID: LinkTrustStore.localID,
            token: typingCode ? "" : saved
        )
        if let data = try? JSONEncoder().encode(hello) {
            channel.send(kind: .hello, payload: data)
        }
    }

    func disconnect() {
        channel?.cancel()
        handleDisconnect(message: "연결을 끊었습니다.")
    }

    func addStroke(_ sample: StrokeSample) {
        ink.add(sample)
        publishInk()
        if let data = try? JSONEncoder().encode(sample) {
            channel?.send(kind: .stroke, payload: data)
        }
    }

    func undo() {
        guard ink.canUndo else { return }
        ink.undo()
        publishInk()
        channel?.send(kind: .undo, payload: Data())
    }

    func redo() {
        guard ink.canRedo else { return }
        ink.redo()
        publishInk()
        channel?.send(kind: .redo, payload: Data())
    }

    func straightenLastStroke(from start: CGPoint, to end: CGPoint, thin: Bool) {
        guard var stroke = ink.strokes.last, !stroke.isEraser else { return }
        if thin {
            stroke.widthFraction *= 0.82
        }
        stroke.points = [clampUnit(start), clampUnit(end)]
        ink.replaceLast(stroke)
        publishInk()
        if let data = try? JSONEncoder().encode(LinkStrokeWire(stroke)) {
            channel?.send(kind: .replaceStroke, payload: data)
        }
    }

    func beginBoxPlacement() {
        isPlacingWhiteRect = true
        settings.isDrawingEnabled = false
    }

    func finishBoxPlacement() {
        isPlacingWhiteRect = false
    }

    func setControlsMac(_ enabled: Bool) {
        controlsMac = enabled
        if enabled, isPlacingWhiteRect {
            isPlacingWhiteRect = false
            settings.isDrawingEnabled = true
        }
    }

    func sendPointer(phase: UInt8, x: CGFloat, y: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) {
        let event = PointerEvent(
            phase: phase,
            x: Float(x),
            y: Float(y),
            dx: Float(dx),
            dy: Float(dy)
        )
        channel?.send(kind: .pointer, payload: event.payload)
    }

    func setBoxes(_ boxes: [LinkBox], send: Bool) {
        self.boxes = boxes
        publishInk()
        guard send, let data = try? JSONEncoder().encode(boxes) else { return }
        channel?.send(kind: .boxes, payload: data)
    }

    func clearInk() {
        guard !ink.strokes.isEmpty else { return }
        ink.clear()
        publishInk()
        channel?.send(kind: .clear, payload: Data())
    }

    func clearAll() {
        let hadInk = !ink.strokes.isEmpty
        let hadBoxes = !boxes.isEmpty
        guard hadInk || hadBoxes else { return }
        if hadInk {
            ink.clear()
        }
        boxes = []
        publishInk()
        channel?.send(kind: .clearAll, payload: Data())
    }

    private static func attachSoleTrust(_ found: [NearbyMac]) -> [NearbyMac] {
        guard found.count == 1, found[0].macID == nil, let onlyID = LinkTrustStore.onlyRemoteID() else {
            return found
        }
        var only = found[0]
        only.macID = onlyID
        return [only]
    }

    private func noteTrustedMac(id: String, name: String?) {
        nearby = nearby.map { mac in
            guard mac.macID == nil, mac.name == name else { return mac }
            var next = mac
            next.macID = id
            return next
        }
    }

    private func clampUnit(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
    }

    private func handle(_ kind: LinkMessageKind, _ payload: Data) {
        switch kind {
        case .accept:
            let trust = try? JSONDecoder().decode(LinkAccept.self, from: payload)
            DispatchQueue.main.async {
                if let trust {
                    let name = self.pendingPeerName ?? self.selectedMac?.name
                    LinkTrustStore.save(token: trust.token, for: trust.macID, name: name)
                    self.noteTrustedMac(id: trust.macID, name: name)
                }
                self.asksForCode = false
                self.isConnected = true
                self.status = "연결됨"
                self.sendInkVisibility()
            }
        case .reject:
            DispatchQueue.main.async {
                self.forgetSelectedTrust()
                self.asksForCode = true
                self.code = ""
                self.channel?.cancel()
                self.handleDisconnect(message: "저장된 연결이 맞지 않습니다. 맥에 표시된 코드를 입력하세요.")
            }
        case .frame:
            enqueueFrame(payload)
        case .clear:
            DispatchQueue.main.async {
                self.ink.clear()
                self.publishInk()
            }
        case .hello, .stroke, .undo, .redo, .replaceStroke, .boxes, .clearAll, .overlayVisible, .pointer:
            break
        }
    }

    func requestCodeEntry() {
        asksForCode = true
        code = ""
        status = "맥에 표시된 코드를 입력하세요."
    }

    private func forgetSelectedTrust() {
        if let name = selectedMac?.name {
            LinkTrustStore.remove(named: name)
        }
        if let macID = selectedMac?.macID {
            LinkTrustStore.remove(macID)
        }
    }

    private func enqueueFrame(_ data: Data) {
        frameQueue.async { [weak self] in
            guard let self else { return }
            self.pendingFrames.append(data)
            self.decodeQueuedFrames()
        }
    }

    private func decodeQueuedFrames() {
        guard !isDecodingFrame else { return }
        isDecodingFrame = true
        while !pendingFrames.isEmpty {
            let data = pendingFrames.removeFirst()
            let image = frameDecoder.image(from: data)
            if let image {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isConnected else { return }
                    self.image = UIImage(cgImage: image)
                    self.onCanvasChange?()
                }
            }
        }
        isDecodingFrame = false
    }

    func sendInkVisibility() {
        channel?.send(kind: .overlayVisible, payload: Data([showsMacInk ? 1 : 0]))
    }

    private func handleDisconnect(message: String) {
        channel = nil
        isConnected = false
        image = nil
        ink = LinkInk()
        boxes = []
        isPlacingWhiteRect = false
        frameQueue.async { [weak self] in
            self?.pendingFrames.removeAll()
            self?.frameDecoder.reset()
        }
        publishInk()
        status = message
    }

    private func publishInk() {
        canUndo = ink.canUndo
        canRedo = ink.canRedo
        onCanvasChange?()
    }

    private func apply(_ found: [NearbyMac]) {
        nearby = found
        if let selectedID, !found.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
        if selectedID == nil {
            selectedID = found.first(where: \.isTrusted)?.id ?? (found.count == 1 ? found[0].id : nil)
        }
        guard !isConnected, channel == nil else { return }
        status = found.isEmpty ? "주변의 맥을 찾는 중" : "맥을 고르고 연결하세요."
    }

    private var selectedMac: NearbyMac? {
        guard let selectedID else { return nil }
        return nearby.first(where: { $0.id == selectedID })
    }
}
