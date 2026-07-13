import Foundation
import Observation
import GhostRaceKit

/// App-wide state: who I am, my segments, my rivals, and any challenge link
/// waiting to be opened.
@Observable
@MainActor
final class AppModel {
    var api: APIClient
    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: "displayName") }
    }
    var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            api = APIClient(baseURL: serverURL, deviceToken: Self.deviceToken())
        }
    }

    var segments: [APIClient.Segment] = []
    var rivals: [APIClient.RivalRecord] = []
    var pendingChallengeToken: String?
    var pendingRaceId: String?
    var registrationError: String?

    init() {
        let defaults = UserDefaults.standard
        self.displayName = defaults.string(forKey: "displayName") ?? ""
        // For local development this is your Mac's LAN address running
        // `npm run dev` in ghost-race/server.
        self.serverURL = defaults.string(forKey: "serverURL") ?? "http://localhost:8787"
        self.api = APIClient(baseURL: self.serverURL, deviceToken: Self.deviceToken())
    }

    /// A stable per-install identity; real auth replaces this post-MVP.
    static func deviceToken() -> String {
        let key = "deviceToken"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    var isOnboarded: Bool { !displayName.isEmpty }

    func bootstrap() async {
        guard isOnboarded else { return }
        await register()
        await refresh()
    }

    func register() async {
        do {
            _ = try await api.registerUser(name: displayName)
            registrationError = nil
        } catch {
            registrationError = "Couldn't reach the GhostRace server at \(serverURL). Check the server address in Settings."
        }
    }

    func refresh() async {
        async let segs = try? api.listSegments()
        async let rivs = try? api.listRivals()
        segments = await segs ?? []
        rivals = await rivs ?? []
    }
}
