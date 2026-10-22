import Foundation

/// 한 번 코드로 인증한 상대의 토큰. 맥과 아이패드가 각자 로컬에만 저장한다.
enum LinkTrustStore {
    private static let localIDKey = "laypen.link.localID"
    private static let tokensKey = "laypen.link.tokens"

    static var localID: String {
        if let existing = UserDefaults.standard.string(forKey: localIDKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: localIDKey)
        return created
    }

    static func token(for remoteID: String) -> String? {
        guard !remoteID.isEmpty else { return nil }
        let map = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String]
        return map?[remoteID]
    }

    static func save(token: String, for remoteID: String) {
        guard !remoteID.isEmpty, !token.isEmpty else { return }
        var map = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        map[remoteID] = token
        UserDefaults.standard.set(map, forKey: tokensKey)
    }

    static func remove(_ remoteID: String) {
        var map = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        map.removeValue(forKey: remoteID)
        UserDefaults.standard.set(map, forKey: tokensKey)
    }
}
