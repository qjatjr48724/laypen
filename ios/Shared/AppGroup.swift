import Foundation

enum AppGroup {
    /// Personal Team에서는 App Groups entitlement가 프로비저닝과 맞지 않을 수 있어
    /// Documents 디렉터리를 사용한다. 유료 계정 + App Group 활성화 시 container를 우선 사용.
    static let identifier = "group.com.laypen.app"
    static let pendingImageFileName = "pending-share-image.jpg"
    static let sessionFileName = "current-session.json"
    static let drawingFileName = "current-drawing.drawing"

    static var containerURL: URL? {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return groupURL
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
}
