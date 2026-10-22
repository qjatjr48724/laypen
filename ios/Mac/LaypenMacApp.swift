import SwiftUI

@main
struct LaypenMacApp: App {
    @StateObject private var host = MacLinkHost()

    var body: some Scene {
        WindowGroup {
            MacHostView(host: host)
        }
        .defaultSize(width: 460, height: 420)
    }
}
