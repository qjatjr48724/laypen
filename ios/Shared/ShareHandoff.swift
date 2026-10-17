import UIKit

/// Share Extension → 메인 앱으로 이미지를 넘기기 위한 핸드오프.
/// App Group이 있으면 파일을 쓰고, Personal Team 등에서는 로컬 전용 클립보드로 보완한다.
enum ShareHandoff {
    static let urlScheme = "laypen"
    static let importURL = URL(string: "laypen://import")!
    private static let pasteboardType = "com.laypen.pending-share-image"

    static func savePendingImage(_ image: UIImage) {
        try? BackgroundSourceLoader.savePendingShareImage(image)
        SessionStore().saveBackground(image)

        // App Group이 없을 때(확장·앱 Documents가 분리됨)를 위한 보완 경로
        if let data = image.jpegData(compressionQuality: 0.92) {
            UIPasteboard.general.setItems(
                [[pasteboardType: data]],
                options: [
                    .localOnly: true,
                    .expirationDate: Date().addingTimeInterval(120)
                ]
            )
        }
    }

    static func loadPendingImage() -> UIImage? {
        if let image = BackgroundSourceLoader.loadPendingShareImage() {
            return image
        }
        if let data = UIPasteboard.general.data(forPasteboardType: pasteboardType),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    static func clearPendingImage() {
        BackgroundSourceLoader.clearPendingShareImage()
        UIPasteboard.general.setData(Data(), forPasteboardType: pasteboardType)
    }
}
