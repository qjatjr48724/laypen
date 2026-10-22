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
    private var latestFrame: Data?
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

    func send(kind: LinkMessageKind, payload: Data) {
        let packet = LinkCodec.encode(kind: kind, payload: payload)
        queue.async { [weak self] in
            guard let self, !self.didEnd else { return }
            if kind == .frame {
                self.latestFrame = packet
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
        if !pending.isEmpty {
            packet = pending.removeFirst()
        } else if let frame = latestFrame {
            latestFrame = nil
            packet = frame
        } else {
            return
        }
        isSending = true
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            self?.queue.async {
                guard let self else { return }
                self.isSending = false
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
        latestFrame = nil
        onEnded?(error)
    }
}
