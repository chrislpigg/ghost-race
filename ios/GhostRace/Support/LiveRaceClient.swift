import Foundation
import GhostRaceKit

/// WebSocket client for live races. Mirrors the message protocol in
/// `ghost-race/server/src/ws.ts` / `race-room.ts`.
@MainActor
final class LiveRaceClient {
    enum Event: Sendable {
        case joined(you: String, peers: [(userId: String, name: String)])
        case peerJoined(name: String)
        case countdown(startAt: Date, serverNow: Date)
        case opponentPosition(EffortPoint)
        case opponentFinished(durationS: Double)
        case result(winnerId: String, reason: String, times: [String: Double?])
        case opponentDisconnected(graceMs: Double)
        case opponentReconnected
        case error(String)
        case socketClosed
    }

    private var task: URLSessionWebSocketTask?
    private let url: URL
    private let raceId: String
    private let deviceToken: String
    var onEvent: ((Event) -> Void)?

    init(url: URL, raceId: String, deviceToken: String) {
        self.url = url
        self.raceId = raceId
        self.deviceToken = deviceToken
    }

    func connect() {
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
        send(["type": "join", "raceId": raceId, "deviceToken": deviceToken])
        receiveLoop()
    }

    func ready() { send(["type": "ready"]) }

    func sendPosition(t: Double, d: Double) { send(["type": "pos", "t": t, "d": d]) }

    func finish(durationS: Double) { send(["type": "finish", "durationS": durationS]) }

    func close() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func send(_ payload: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        task.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .failure:
                    self.onEvent?(.socketClosed)
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receiveLoop()
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        switch type {
        case "joined":
            let peers = (json["peers"] as? [[String: Any]] ?? []).compactMap { peer -> (String, String)? in
                guard let id = peer["userId"] as? String, let name = peer["name"] as? String else { return nil }
                return (id, name)
            }
            onEvent?(.joined(you: json["you"] as? String ?? "", peers: peers))
        case "peer_joined":
            onEvent?(.peerJoined(name: json["name"] as? String ?? "Rival"))
        case "countdown":
            guard let startAt = json["startAt"] as? Double, let serverNow = json["serverNow"] as? Double else { return }
            onEvent?(.countdown(
                startAt: Date(timeIntervalSince1970: startAt / 1000),
                serverNow: Date(timeIntervalSince1970: serverNow / 1000)
            ))
        case "pos":
            guard let t = json["t"] as? Double, let d = json["d"] as? Double else { return }
            onEvent?(.opponentPosition(EffortPoint(t: t, d: d)))
        case "peer_finished":
            onEvent?(.opponentFinished(durationS: json["durationS"] as? Double ?? 0))
        case "result":
            let times = (json["times"] as? [String: Any] ?? [:]).mapValues { $0 as? Double }
            onEvent?(.result(
                winnerId: json["winnerId"] as? String ?? "",
                reason: json["reason"] as? String ?? "finish",
                times: times
            ))
        case "peer_disconnected":
            onEvent?(.opponentDisconnected(graceMs: json["graceMs"] as? Double ?? 0))
        case "peer_reconnected":
            onEvent?(.opponentReconnected)
        case "error":
            onEvent?(.error(json["message"] as? String ?? "unknown error"))
        default:
            break
        }
    }
}
