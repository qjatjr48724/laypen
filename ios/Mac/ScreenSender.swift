import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import ScreenCaptureKit
import VideoToolbox

/// 메인 화면을 보낸다. 가만히 있는 화면은 바뀐 부분만 압축하고, 압축된 장면은 순서대로 보낸다.
/// 선로가 밀릴 때만 아직 압축하지 않은 원본을 건너뛴다.
final class ScreenSender: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((Data, @escaping () -> Void) -> Void)?
    var onStopped: ((String) -> Void)?

    private let context = CIContext()
    private let queue = DispatchQueue(label: "laypen.screen.capture")
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var startGeneration = 0
    private var session: VTCompressionSession?
    private var sessionSize = CGSize.zero
    private var useJPEG = false
    private var frameIndex: Int64 = 0
    private var needsKeyframe = true
    /// 아직 선로에 나가지 않은 압축 장면. 이 수를 넘으면 원본만 건너뛴다.
    private var unsentFrames = 0
    private let unsentLimit = 6

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
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
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

    private func retireStream() -> Int {
        stateLock.lock()
        startGeneration += 1
        let generation = startGeneration
        let active = stream
        stream = nil
        let compression = session
        session = nil
        sessionSize = .zero
        useJPEG = false
        needsKeyframe = true
        unsentFrames = 0
        stateLock.unlock()
        if let compression {
            VTCompressionSessionInvalidate(compression)
        }
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
        guard type == .screen, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        stateLock.lock()
        let saturated = unsentFrames >= unsentLimit
        stateLock.unlock()
        if saturated { return }
        if useJPEG {
            if let jpeg = jpegData(from: pixelBuffer) {
                deliver(jpeg)
            }
            return
        }
        if !encodeH264(pixelBuffer) {
            useJPEG = true
            if let jpeg = jpegData(from: pixelBuffer) {
                deliver(jpeg)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStopped?(error.localizedDescription)
    }

    private func encodeH264(_ pixelBuffer: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 1, height > 1 else { return false }
        if session == nil || sessionSize != CGSize(width: width, height: height) {
            guard openEncoder(width: width, height: height) else {
                useJPEG = true
                return false
            }
        }
        guard let session else { return false }
        frameIndex += 1
        let force = needsKeyframe
        let properties: CFDictionary? = force
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            : nil
        var flags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: CMTime(value: frameIndex, timescale: 60),
            duration: .invalid,
            frameProperties: properties,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        if status == noErr {
            needsKeyframe = false
        }
        return status == noErr
    }

    private func openEncoder(width: Int, height: Int) -> Bool {
        if let session {
            VTCompressionSessionInvalidate(session)
            self.session = nil
        }
        needsKeyframe = true
        var created: VTCompressionSession?
        let spec: CFDictionary = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: kCFBooleanTrue as Any
        ] as CFDictionary
        var status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: spec,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: Self.compressionOutput,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &created
        )
        if status != noErr || created == nil {
            status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: Int32(width),
                height: Int32(height),
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: nil,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: Self.compressionOutput,
                refcon: Unmanaged.passUnretained(self).toOpaque(),
                compressionSessionOut: &created
            )
        }
        guard status == noErr, let created else { return false }
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: 120))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 2))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: 60))
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: 4_000_000))
        VTCompressionSessionPrepareToEncodeFrames(created)
        session = created
        sessionSize = CGSize(width: width, height: height)
        return true
    }

    private static let compressionOutput: VTCompressionOutputCallback = { refcon, _, status, _, sample in
        guard let refcon else { return }
        let sender = Unmanaged<ScreenSender>.fromOpaque(refcon).takeUnretainedValue()
        guard status == noErr, let sample, let packet = sender.packet(from: sample) else { return }
        sender.deliver(packet)
    }

    private func packet(from sample: CMSampleBuffer) -> Data? {
        guard let buffer = CMSampleBufferGetDataBuffer(sample) else { return nil }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            buffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &pointer
        ) == kCMBlockBufferNoErr, let pointer, length > 0 else { return nil }
        let keyframe = Self.isKeyframe(sample)
        let sets = keyframe ? Self.parameterSets(from: sample) : []
        let bytes = Data(bytes: pointer, count: length)
        return LinkVideoFrame(isKeyframe: keyframe, parameterSets: sets, sample: bytes).data
    }

    private static func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [NSDictionary],
              let first = attachments.first else { return true }
        return (first[kCMSampleAttachmentKey_NotSync] as? Bool) != true
    }

    private static func parameterSets(from sample: CMSampleBuffer) -> [Data] {
        guard let format = CMSampleBufferGetFormatDescription(sample) else { return [] }
        var sets: [Data] = []
        var index = 0
        while true {
            var pointer: UnsafePointer<UInt8>?
            var length = 0
            var count = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &length,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: nil
            )
            guard status == noErr, let pointer, length > 0 else { break }
            sets.append(Data(bytes: pointer, count: length))
            index += 1
            if count > 0, index >= count { break }
        }
        return sets
    }

    private func deliver(_ data: Data) {
        stateLock.lock()
        unsentFrames += 1
        stateLock.unlock()
        guard let onFrame else {
            noteFrameSent()
            return
        }
        onFrame(data) { [weak self] in
            self?.noteFrameSent()
        }
    }

    private func noteFrameSent() {
        stateLock.lock()
        unsentFrames = max(0, unsentFrames - 1)
        stateLock.unlock()
    }

    private func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let key = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [key: 0.4])
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
