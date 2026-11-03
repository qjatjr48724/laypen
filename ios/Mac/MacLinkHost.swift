import AppKit
import Foundation
import Network

final class MacLinkHost: ObservableObject {
    @Published private(set) var code: String
    @Published private(set) var status = "아이패드에서 이 코드를 입력하세요."
    @Published private(set) var captureWarning: String?
    @Published private(set) var controlWarning: String?
    @Published private(set) var isConnected = false

    private var listener: NWListener?
    private var channel: LinkChannel?
    private let channelLock = NSLock()
    private let sender = ScreenSender()
    private let overlay = OverlayPanel()
    private var didStart = false
    private var captureTask: Task<Void, Never>?
    private var restartWork: DispatchWorkItem?
    private var lastCaptureStop = Date.distantPast
    private var waitForWake = false
    private let displayResume = DisplayResumeObserver()

    init() {
        code = Self.makeCode()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        refreshCaptureAccess(prompt: true)
        refreshControlAccess(prompt: true)
        sender.onFrame = { [weak self] data, done in
            guard let self, let channel = self.currentChannel() else {
                done()
                return
            }
            channel.send(kind: .frame, payload: data, onFlushed: done)
        }
        sender.onStopped = { [weak self] _ in
            DispatchQueue.main.async {
                self?.captureStopped()
            }
        }
        displayResume.onResume = { [weak self] in
            DispatchQueue.main.async {
                self?.displayResumed()
            }
        }
        displayResume.start()
        do {
            try startListener()
        } catch {
            status = "연결을 열지 못했습니다. \(error.localizedDescription)"
        }
    }

    func regenerateCode() {
        guard !isConnected else { return }
        code = Self.makeCode()
        status = "아이패드에서 이 코드를 입력하세요."
    }

    func clearStrokes() {
        overlay.clear()
        currentChannel()?.send(kind: .clear, payload: Data())
    }

    func openCaptureSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    private func startListener() throws {
        let listener = try NWListener(using: LinkService.parameters())
        var txt = NWTXTRecord()
        txt["id"] = LinkTrustStore.localID
        listener.service = NWListener.Service(
            name: Host.current().localizedName ?? "Laypen",
            type: LinkService.type,
            txtRecord: txt
        )
        listener.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                if case .failed(let error) = state {
                    self?.status = "주변 알림을 시작하지 못했습니다. \(error.localizedDescription)"
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        DispatchQueue.main.async {
            guard self.currentChannel() == nil else {
                connection.cancel()
                return
            }
            let channel = LinkChannel(connection)
            self.setChannel(channel)
            channel.onMessage = { [weak self] kind, payload in
                DispatchQueue.main.async {
                    self?.handle(kind, payload)
                }
            }
            channel.onEnded = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handleDisconnect()
                }
            }
            channel.start()
        }
    }

    private func handle(_ kind: LinkMessageKind, _ payload: Data) {
        switch kind {
        case .hello:
            guard let hello = try? JSONDecoder().decode(LinkHello.self, from: payload) else {
                reject()
                return
            }
            let trusted = !hello.token.isEmpty && LinkTrustStore.token(for: hello.peerID) == hello.token
            let codeMatches = hello.code.count == 4 && hello.code == code
            guard trusted || codeMatches else {
                reject()
                return
            }
            let issued = trusted ? hello.token : UUID().uuidString
            if !trusted {
                LinkTrustStore.save(token: issued, for: hello.peerID)
            }
            let accept = LinkAccept(macID: LinkTrustStore.localID, token: issued)
            if let data = try? JSONEncoder().encode(accept) {
                currentChannel()?.send(kind: .accept, payload: data)
            }
            beginSession()
        case .stroke:
            guard let sample = try? JSONDecoder().decode(StrokeSample.self, from: payload) else { return }
            overlay.add(sample)
        case .undo:
            overlay.undo()
        case .redo:
            overlay.redo()
        case .clear:
            overlay.clear()
        case .replaceStroke:
            let stroke = (try? JSONDecoder().decode(LinkStrokeWire.self, from: payload))?.stroke()
                ?? (try? JSONDecoder().decode(LinkStroke.self, from: payload))
            guard let stroke else { return }
            overlay.replaceLast(stroke)
        case .boxes:
            guard let boxes = try? JSONDecoder().decode([LinkBox].self, from: payload) else { return }
            overlay.setBoxes(boxes)
        case .clearAll:
            overlay.clearAll()
        case .overlayVisible:
            overlay.setContentVisible(payload.first != 0)
        case .replaceInk:
            guard let wires = try? JSONDecoder().decode([LinkStrokeWire].self, from: payload) else { return }
            overlay.replaceInk(wires.map { $0.stroke() })
        case .pointer:
            guard let event = PointerEvent(data: payload) else { return }
            MacPointer.apply(event)
        case .frame, .accept, .reject:
            break
        }
    }

    private func beginSession() {
        isConnected = true
        status = "아이패드가 연결되었습니다."
        overlay.clearAll()
        overlay.setContentVisible(true)
        refreshCaptureAccess(prompt: false)
        guard CGPreflightScreenCaptureAccess() else {
            captureWarning = "화면 기록 권한이 없습니다. 허용한 뒤 아이패드에서 다시 연결하세요."
            return
        }
        captureWarning = nil
        waitForWake = false
        startCapture(delay: 0)
    }

    /// 캡처가 죽으면 한 번 다시 연다. 바로 또 죽으면 화면이 깨어날 때까지 기다린다.
    private func captureStopped() {
        guard isConnected, !waitForWake else { return }
        let now = Date()
        if now.timeIntervalSince(lastCaptureStop) < 2 {
            waitForWake = true
            return
        }
        lastCaptureStop = now
        scheduleRestart()
    }

    /// 화면 보호기·잠자기가 끝나면 스트림을 새로 만든다.
    private func displayResumed() {
        guard isConnected else { return }
        waitForWake = false
        lastCaptureStop = .distantPast
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard isConnected else { return }
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.startCapture(delay: 0)
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func startCapture(delay: TimeInterval) {
        guard isConnected else { return }
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self else { return }
            guard !Task.isCancelled, self.isConnected, CGPreflightScreenCaptureAccess() else { return }
            do {
                try await self.sender.start()
                if !self.isConnected {
                    self.sender.stop()
                    return
                }
                await MainActor.run {
                    if self.isConnected {
                        self.captureWarning = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.captureWarning = error.localizedDescription
                }
            }
        }
    }

    private func reject() {
        currentChannel()?.send(kind: .reject, payload: Data())
        currentChannel()?.cancel()
        setChannel(nil)
        status = "코드가 맞지 않아 연결을 거절했습니다."
    }

    private func handleDisconnect() {
        guard channel != nil || isConnected else { return }
        restartWork?.cancel()
        restartWork = nil
        waitForWake = false
        captureTask?.cancel()
        sender.stop()
        MacPointer.releaseButton()
        setChannel(nil)
        isConnected = false
        status = "연결이 끊어졌습니다. 아이패드에서 다시 연결할 수 있습니다."
    }

    private func refreshControlAccess(prompt: Bool) {
        guard !MacPointer.isTrusted else {
            controlWarning = nil
            return
        }
        controlWarning = "아이패드에서 맥을 조작하려면 손쉬운 사용 권한이 필요합니다."
        if prompt {
            MacPointer.prompt()
        }
    }

    func openControlSettings() {
        MacPointer.openSettings()
        refreshControlAccess(prompt: false)
    }

    private func refreshCaptureAccess(prompt: Bool) {
        guard !CGPreflightScreenCaptureAccess() else {
            captureWarning = nil
            return
        }
        captureWarning = "화면 기록 권한이 없으면 아이패드에 맥 화면을 보낼 수 없습니다."
        if prompt {
            CGRequestScreenCaptureAccess()
        }
    }

    private func currentChannel() -> LinkChannel? {
        channelLock.lock()
        defer { channelLock.unlock() }
        return channel
    }

    private func setChannel(_ channel: LinkChannel?) {
        channelLock.lock()
        self.channel = channel
        channelLock.unlock()
    }

    private static func makeCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }
}

/// 화면 보호기·잠자기가 끝난 알림. 앱이 백그라운드여도 바로 받는다.
private final class DisplayResumeObserver: NSObject {
    var onResume: (() -> Void)?

    func start() {
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.didstop", "com.apple.screenIsUnlocked"] {
            distributed.addObserver(
                self,
                selector: #selector(resume(_:)),
                name: Notification.Name(name),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(resume(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resume(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resume(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func resume(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.onResume?()
        }
    }
}
