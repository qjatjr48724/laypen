import Foundation

/// 한 번 코드로 인증한 상대의 토큰. 맥과 아이패드가 각자 로컬에만 저장한다.
enum LinkTrustStore {
    private static let localIDKey = "laypen.link.localID"
    private static let tokensKey = "laypen.link.tokens"
    /// Bonjour에 기기 번호가 안 실려도 이름으로 다시 찾을 수 있게 한다.
    private static let namesKey = "laypen.link.names"

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

    static func token(named name: String) -> String? {
        guard let remoteID = remoteID(named: name) else { return nil }
        return token(for: remoteID)
    }

    static func remoteID(named name: String) -> String? {
        guard !name.isEmpty else { return nil }
        let names = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]
        return names?[name]
    }

    /// 저장한 맥이 하나뿐이면 그 기기 번호를 돌려준다.
    static func onlyRemoteID() -> String? {
        let map = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        guard map.count == 1 else { return nil }
        return map.keys.first
    }

    static func save(token: String, for remoteID: String, name: String? = nil) {
        guard !remoteID.isEmpty, !token.isEmpty else { return }
        var map = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        map[remoteID] = token
        UserDefaults.standard.set(map, forKey: tokensKey)
        guard let name, !name.isEmpty else { return }
        var names = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        names[name] = remoteID
        UserDefaults.standard.set(names, forKey: namesKey)
    }

    static func remove(_ remoteID: String) {
        var map = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        map.removeValue(forKey: remoteID)
        UserDefaults.standard.set(map, forKey: tokensKey)
        var names = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        names = names.filter { $0.value != remoteID }
        UserDefaults.standard.set(names, forKey: namesKey)
    }
}
