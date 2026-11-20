import SwiftUI

@main
struct DevinRemoteApp: App {
    @StateObject private var api = API()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var api: API
    var body: some View {
        if api.serverURL.isEmpty || api.remoteKey.isEmpty {
            SetupView()
        } else {
            SessionsView()
        }
    }
}
