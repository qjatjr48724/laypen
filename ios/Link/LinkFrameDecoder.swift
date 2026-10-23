import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import VideoToolbox

struct LinkVideoFrame {
    static let h264: UInt8 = 1

    var isKeyframe: Bool
    var parameterSets: [Data]
    var sample: Data

    var data: Data {
        var data = Data()
        data.append(Self.h264)
        data.append(isKeyframe ? 1 : 0)
        var count = UInt16(parameterSets.count).bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        for set in parameterSets {
            var length = UInt16(min(set.count, Int(UInt16.max))).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(set.prefix(Int(UInt16.max)))
        }
        data.append(sample)
        return data
    }

    init(isKeyframe: Bool, parameterSets: [Data], sample: Data) {
        self.isKeyframe = isKeyframe
        self.parameterSets = parameterSets
        self.sample = sample
    }

    init?(data: Data) {
        guard data.count > 4, data[data.startIndex] == Self.h264 else { return nil }
        var offset = 1
        func byte() -> UInt8? {
            guard offset < data.count else { return nil }
            let value = data[data.index(data.startIndex, offsetBy: offset)]
            offset += 1
            return value
        }
        func u16() -> Int? {
            guard offset + 1 < data.count else { return nil }
            let start = data.index(data.startIndex, offsetBy: offset)
            offset += 2
            return (Int(data[start]) << 8) | Int(data[data.index(after: start)])
        }
        guard let flag = byte(), let setCount = u16(), setCount < 8 else { return nil }
        var sets: [Data] = []
        for _ in 0..<setCount {
            guard let length = u16(), length > 0, offset + length <= data.count else { return nil }
            let start = data.index(data.startIndex, offsetBy: offset)
            let end = data.index(start, offsetBy: length)
            sets.append(Data(data[start..<end]))
            offset += length
        }
        guard offset < data.count else { return nil }
        isKeyframe = flag == 1
        parameterSets = sets
        let sampleStart = data.index(data.startIndex, offsetBy: offset)
        sample = Data(data[sampleStart...])
    }
}

/// 아이패드에서 H.264 화면 장을 순서대로 푼다. 장은 서로 의존하므로 중간을 건너뛰지 않는다.
final class LinkFrameDecoder {
    private var format: CMFormatDescription?
    private var session: VTDecompressionSession?
    private var formatToken: [Data] = []
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let lock = NSLock()
    private var decodedImage: CGImage?
    private var time: Int64 = 0

    func reset() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        format = nil
        formatToken = []
    }

    func image(from data: Data) -> CGImage? {
        if data.first == 0xFF {
            return Self.jpeg(data)
        }
        guard let frame = LinkVideoFrame(data: data) else { return nil }
        if frame.isKeyframe, !frame.parameterSets.isEmpty, frame.parameterSets != formatToken {
            guard prepare(parameterSets: frame.parameterSets) else { return nil }
        }
        guard let session, let format else { return nil }
        guard let sample = sampleBuffer(frame.sample, format: format) else { return nil }
        lock.lock()
        decodedImage = nil
        lock.unlock()
        var flags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [],
            frameRefcon: nil,
            infoFlagsOut: &flags
        )
        guard status == noErr else { return nil }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        lock.lock()
        let image = decodedImage
        decodedImage = nil
        lock.unlock()
        return image
    }

    private func prepare(parameterSets sets: [Data]) -> Bool {
        if let session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }
        let objects = sets.map { $0 as NSData }
        var pointers = objects.map { UnsafePointer<UInt8>($0.bytes.assumingMemoryBound(to: UInt8.self)) }
        var sizes = objects.map(\.length)
        var description: CMFormatDescription?
        let created = pointers.withUnsafeMutableBufferPointer { pointerBuffer in
            sizes.withUnsafeMutableBufferPointer { sizeBuffer in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: objects.count,
                    parameterSetPointers: pointerBuffer.baseAddress!,
                    parameterSetSizes: sizeBuffer.baseAddress!,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &description
                )
            }
        }
        guard created == noErr, let description else { return false }
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refcon, _, status, _, imageBuffer, _, _ in
                guard status == noErr, let imageBuffer, let refcon else { return }
                let decoder = Unmanaged<LinkFrameDecoder>.fromOpaque(refcon).takeUnretainedValue()
                let source = CIImage(cvPixelBuffer: imageBuffer)
                let image = decoder.context.createCGImage(source, from: source.extent)
                decoder.lock.lock()
                decoder.decodedImage = image
                decoder.lock.unlock()
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        var session: VTDecompressionSession?
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]
        let opened = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: description,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        guard opened == noErr, let session else { return false }
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        format = description
        formatToken = sets
        self.session = session
        return true
    }

    private func sampleBuffer(_ sample: Data, format: CMFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        let length = sample.count
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: length,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: 0,
            blockBufferOut: &block
        ) == kCMBlockBufferNoErr, let block else { return nil }
        let copied = sample.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }
        time += 1
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: time, timescale: 60),
            decodeTimeStamp: .invalid
        )
        var size = length
        var buffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &buffer
        )
        guard status == noErr else { return nil }
        return buffer
    }

    private static func jpeg(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
