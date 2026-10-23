import Foundation
import Network

/// 길이 헤더로 나눈 TCP 채널. 보내기 전에 연결이 준비될 때까지 메시지를 쌓는다.
final class LinkChannel {
    var onMessage: ((LinkMessageKind, Data) -> Void)?
    var onEnded: ((NWError?) -> Void)?

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "laypen.link.channel")
    private var framer = LinkFramer()
    private var pending: [Data] = []
    private var frames: [(packet: Data, flush: (() -> Void)?)] = []
    private var inflightFlush: (() -> Void)?
    private var isSending = false
    private var isReady = false
    private var didEnd = false

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isReady = true
                self.receive()
                self.pump()
            case .failed(let error):
                self.finish(error)
            case .cancelled:
                self.finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(kind: LinkMessageKind, payload: Data, onFlushed: (() -> Void)? = nil) {
        let packet = LinkCodec.encode(kind: kind, payload: payload)
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.didEnd else {
                onFlushed?()
                return
            }
            if kind == .frame {
                self.frames.append((packet, onFlushed))
            } else {
                self.pending.append(packet)
            }
            self.pump()
        }
    }

    func cancel() {
        queue.async { [weak self] in
            self?.connection.cancel()
        }
    }

    private func pump() {
        guard isReady, !isSending else { return }
        let packet: Data
        var flush: (() -> Void)?
        if !pending.isEmpty {
            packet = pending.removeFirst()
        } else if !frames.isEmpty {
            let frame = frames.removeFirst()
            packet = frame.packet
            flush = frame.flush
        } else {
            return
        }
        isSending = true
        inflightFlush = flush
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            self?.queue.async {
                guard let self else { return }
                let done = self.inflightFlush
                self.inflightFlush = nil
                self.isSending = false
                done?()
                if let error {
                    self.finish(error)
                    return
                }
                self.pump()
            }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.didEnd else { return }
            if let data, !data.isEmpty {
                let messages = self.framer.append(data)
                for (kind, payload) in messages {
                    self.onMessage?(kind, payload)
                }
            }
            if isComplete || error != nil {
                self.finish(error)
                return
            }
            self.receive()
        }
    }

    private func finish(_ error: NWError?) {
        guard !didEnd else { return }
        didEnd = true
        isReady = false
        pending.removeAll()
        let waiting = frames.map(\.flush)
        frames.removeAll()
        let inflight = inflightFlush
        inflightFlush = nil
        waiting.forEach { $0?() }
        inflight?()
        onEnded?(error)
    }
}
