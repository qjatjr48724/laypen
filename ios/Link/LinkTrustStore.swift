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

    /// 예전에 코드로 연결해 둔 맥 목록. 이름 있는 항목만 보여 주고, 이름 없는 중복 토큰은 정리한다.
    static func savedPeers() -> [SavedPeer] {
        pruneOrphanTokens()
        let tokens = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        let names = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        var idToName: [String: String] = [:]
        for (name, remoteID) in names where tokens[remoteID] != nil {
            idToName[remoteID] = name
        }

        let named = idToName.keys.sorted().map { remoteID in
            SavedPeer(id: remoteID, name: idToName[remoteID] ?? "저장된 맥")
        }
        if !named.isEmpty {
            return named
        }

        // 이름 기록이 없을 때만 토큰만 있는 항목을 하나로 보여 준다.
        guard let only = tokens.keys.sorted().first else { return [] }
        return [SavedPeer(id: only, name: "저장된 맥")]
    }

    /// 이름은 있는데 토큰 id와 안 맞는 고아 항목을 지운다. (같은 맥이 두 줄로 뜨던 원인)
    private static func pruneOrphanTokens() {
        var tokens = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        let names = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        let referenced = Set(names.values)
        guard !referenced.isEmpty else { return }
        let before = tokens.count
        tokens = tokens.filter { referenced.contains($0.key) }
        guard tokens.count != before else { return }
        UserDefaults.standard.set(tokens, forKey: tokensKey)
    }

    struct SavedPeer: Identifiable, Hashable {
        var id: String
        var name: String
    }

    static func save(token: String, for remoteID: String, name: String? = nil) {
        guard !remoteID.isEmpty, !token.isEmpty else { return }
        var map = UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
        map[remoteID] = token
        if let name, !name.isEmpty {
            var names = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:]
            // 같은 이름에 예전 id가 있으면 토큰도 같이 교체한다.
            if let oldID = names[name], oldID != remoteID {
                map.removeValue(forKey: oldID)
            }
            names[name] = remoteID
            UserDefaults.standard.set(names, forKey: namesKey)
        }
        UserDefaults.standard.set(map, forKey: tokensKey)
        pruneOrphanTokens()
    }

    static func remove(named name: String) {
        guard let remoteID = remoteID(named: name) else { return }
        remove(remoteID)
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
