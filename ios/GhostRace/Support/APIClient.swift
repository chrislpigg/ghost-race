import Foundation
import GhostRaceKit

/// Thin async REST client for the GhostRace server. Mirrors
/// `ghost-race/server/src/api.ts` — if a route changes there, change it here.
struct APIClient: Sendable {
    let baseURL: String
    let deviceToken: String

    enum APIError: LocalizedError {
        case badStatus(Int, String)
        case badURL

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let message): return "Server error \(code): \(message)"
            case .badURL: return "Invalid server URL"
            }
        }
    }

    // MARK: - Wire models (match the server's JSON)

    struct User: Codable, Sendable {
        let id: String
        let name: String
    }

    struct Segment: Codable, Identifiable, Sendable {
        let id: String
        let ownerId: String
        let name: String
        let activityType: ActivityType
        let polyline: [Coordinate]
        let distanceM: Double
        let gateRadiusM: Double
        let createdAt: Double
    }

    struct Effort: Codable, Identifiable, Sendable {
        let id: String
        let segmentId: String
        let userId: String
        let startedAt: Double
        let durationS: Double
        let points: [EffortPoint]
    }

    struct Challenge: Codable, Sendable {
        let id: String
        let token: String
        let segmentId: String
        let effortId: String
        let challengerId: String
        let status: String
        var url: String?
    }

    struct ChallengeDetails: Codable, Sendable {
        let challenge: Challenge
        let ghost: Effort
        let segment: Segment
        let challengerName: String
    }

    struct RivalRecord: Codable, Identifiable, Sendable {
        let rivalId: String
        let rivalName: String
        let wins: Int
        let losses: Int
        let lastRaceAt: Double
        var id: String { rivalId }
    }

    struct ChallengeOutcome: Codable, Sendable {
        struct Result: Codable, Sendable {
            let winnerId: String
            let winnerTimeS: Double?
            let loserTimeS: Double?
        }
        let result: Result
    }

    struct RaceRoom: Codable, Sendable {
        let raceId: String
    }

    // MARK: - Endpoints

    func registerUser(name: String) async throws -> User {
        try await request("POST", "/api/users", body: ["deviceToken": deviceToken, "name": name])
    }

    func listSegments() async throws -> [Segment] {
        try await request("GET", "/api/segments")
    }

    func createSegment(
        name: String,
        activityType: ActivityType,
        polyline: [Coordinate],
        distanceM: Double
    ) async throws -> Segment {
        try await request(
            "POST", "/api/segments",
            body: [
                "name": name,
                "activityType": activityType.rawValue,
                "polyline": polyline.map { ["lat": $0.lat, "lon": $0.lon] },
                "distanceM": distanceM,
            ]
        )
    }

    /// My efforts on a segment, fastest first.
    func listMyEfforts(segmentId: String) async throws -> [Effort] {
        try await request("GET", "/api/segments/\(segmentId)/efforts")
    }

    func createEffort(
        segmentId: String,
        startedAt: Date,
        durationS: Double,
        points: [EffortPoint]
    ) async throws -> Effort {
        try await request(
            "POST", "/api/efforts",
            body: [
                "segmentId": segmentId,
                "startedAt": startedAt.timeIntervalSince1970 * 1000,
                "durationS": durationS,
                "points": points.map { ["t": $0.t, "d": $0.d] },
            ]
        )
    }

    func createChallenge(effortId: String) async throws -> Challenge {
        try await request("POST", "/api/challenges", body: ["effortId": effortId])
    }

    func challengeDetails(token: String) async throws -> ChallengeDetails {
        try await request("GET", "/api/challenges/\(token)")
    }

    func acceptChallenge(token: String) async throws -> Challenge {
        try await request("POST", "/api/challenges/\(token)/accept")
    }

    func completeChallenge(
        token: String,
        startedAt: Date,
        durationS: Double,
        points: [EffortPoint]
    ) async throws -> ChallengeOutcome {
        try await request(
            "POST", "/api/challenges/\(token)/result",
            body: [
                "startedAt": startedAt.timeIntervalSince1970 * 1000,
                "durationS": durationS,
                "points": points.map { ["t": $0.t, "d": $0.d] },
            ]
        )
    }

    func listRivals() async throws -> [RivalRecord] {
        try await request("GET", "/api/rivals")
    }

    func createRace(segmentId: String?) async throws -> RaceRoom {
        var body: [String: Any] = [:]
        if let segmentId { body["segmentId"] = segmentId }
        return try await request("POST", "/api/races", body: body)
    }

    /// ws:// URL for the live race socket, derived from the http base URL.
    func webSocketURL() throws -> URL {
        guard var components = URLComponents(string: baseURL) else { throw APIError.badURL }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        guard let url = components.url else { throw APIError.badURL }
        return url
    }

    // MARK: - Plumbing

    private func request<T: Decodable>(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(deviceToken, forHTTPHeaderField: "x-device-token")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError.badStatus(status, message ?? "unknown")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
