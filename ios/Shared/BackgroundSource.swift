import UIKit

/// 배경 이미지 공급. MVP는 스크린샷/공유 이미지.
/// 이후 시스템 오버레이 등이 가능해지면 이 계층만 교체한다.
protocol BackgroundSource {
    var image: UIImage? { get }
}

struct ScreenshotImageSource: BackgroundSource {
    let image: UIImage?
}

enum BackgroundSourceLoader {
    static func loadPendingShareImage() -> UIImage? {
        guard let url = AppGroup.containerURL?.appendingPathComponent(AppGroup.pendingImageFileName),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    static func savePendingShareImage(_ image: UIImage) throws {
        guard let url = AppGroup.containerURL?.appendingPathComponent(AppGroup.pendingImageFileName),
              let data = image.jpegData(compressionQuality: 0.92) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    static func clearPendingShareImage() {
        guard let url = AppGroup.containerURL?.appendingPathComponent(AppGroup.pendingImageFileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
