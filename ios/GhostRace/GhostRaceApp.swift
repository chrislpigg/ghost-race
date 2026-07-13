import SwiftUI

@main
struct GhostRaceApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
                .onOpenURL { url in
                    // ghostrace://challenge/<token> and ghostrace://race/<raceId>
                    guard url.scheme == "ghostrace" else { return }
                    let value = url.lastPathComponent
                    guard !value.isEmpty else { return }
                    switch url.host {
                    case "challenge": model.pendingChallengeToken = value
                    case "race": model.pendingRaceId = value
                    default: break
                    }
                }
                .task { await model.bootstrap() }
                .tint(.grBlaze)
                .preferredColorScheme(.dark)
        }
    }
}
