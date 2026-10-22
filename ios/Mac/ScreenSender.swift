import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import ScreenCaptureKit

/// 메인 화면을 주기적으로 JPEG로 만들어 보낸다. Laypen 창은 캡처에서 빼서 획이 영상에 겹치지 않게 한다.
final class ScreenSender: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((Data) -> Void)?
    var onStopped: ((String) -> Void)?

    private let context = CIContext()
    private let queue = DispatchQueue(label: "laypen.screen.capture")
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var startGeneration = 0
    private let jpegQuality = 0.45

    func start() async throws {
        let generation = retireStream()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let mainID = Self.mainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
            throw ScreenSenderError.noDisplay
        }

        let bundleID = Bundle.main.bundleIdentifier
        let excluded = content.applications.filter { $0.bundleIdentifier == bundleID }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excluded,
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        let fitted = Self.fittedSize(width: display.width, height: display.height, maxSide: 1440)
        configuration.width = fitted.width
        configuration.height = fitted.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 8)
        configuration.queueDepth = 3

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        guard keep(stream, generation: generation) else {
            try? await stream.stopCapture()
            return
        }
    }

    func stop() {
        _ = retireStream()
    }

    /// 진행 중인 캡처를 멈추고 세대를 올린다. 늦게 끝난 start는 이 세대가 아니면 스트림을 버린다.
    private func retireStream() -> Int {
        stateLock.lock()
        startGeneration += 1
        let generation = startGeneration
        let active = stream
        stream = nil
        stateLock.unlock()
        if let active {
            Task { try? await active.stopCapture() }
        }
        return generation
    }

    private func keep(_ stream: SCStream, generation: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard generation == startGeneration else { return false }
        self.stream = stream
        return true
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let jpeg = jpegData(from: pixelBuffer) else { return }
        onFrame?(jpeg)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStopped?(error.localizedDescription)
    }

    private func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let key = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return context.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [key: jpegQuality]
        )
    }

    private static func mainDisplayID() -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.main,
           let number = screen.deviceDescription[key] as? NSNumber {
            return number.uint32Value
        }
        return CGMainDisplayID()
    }

    private static func fittedSize(width: Int, height: Int, maxSide: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        let scale = longest > maxSide ? Double(maxSide) / Double(longest) : 1
        let fittedWidth = max(2, Int((Double(width) * scale).rounded(.down)) / 2 * 2)
        let fittedHeight = max(2, Int((Double(height) * scale).rounded(.down)) / 2 * 2)
        return (fittedWidth, fittedHeight)
    }
}

enum ScreenSenderError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "보낼 화면을 찾지 못했습니다."
        }
    }
}
