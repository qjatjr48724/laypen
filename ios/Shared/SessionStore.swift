import Foundation
import UIKit

struct SessionMetadata: Codable, Equatable {
    var updatedAt: Date
    var hasBackgroundImage: Bool
}

/// 현재 작업 세션 메타데이터 + 배경 이미지 로컬 보관.
final class SessionStore {
    private let backgroundFileName = "current-background.jpg"

    func saveBackground(_ image: UIImage) {
        guard let url = AppGroup.containerURL?.appendingPathComponent(backgroundFileName),
              let data = image.jpegData(compressionQuality: 0.92) else { return }
        try? data.write(to: url, options: .atomic)
        saveMetadata(SessionMetadata(updatedAt: Date(), hasBackgroundImage: true))
    }

    func loadBackground() -> UIImage? {
        guard let url = AppGroup.containerURL?.appendingPathComponent(backgroundFileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func saveMetadata(_ metadata: SessionMetadata) {
        guard let url = AppGroup.containerURL?.appendingPathComponent(AppGroup.sessionFileName),
              let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func loadMetadata() -> SessionMetadata? {
        guard let url = AppGroup.containerURL?.appendingPathComponent(AppGroup.sessionFileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionMetadata.self, from: data)
    }
}
