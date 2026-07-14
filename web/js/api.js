/**
 * REST client for the GhostRace server. Same wire shape as APIClient.swift.
 * Served from the same origin, so requests are relative and there's no CORS.
 */

const TOKEN_KEY = "ghostrace.deviceToken";

/** A stable per-browser identity; real auth replaces this post-MVP. */
export function deviceToken() {
  let token = localStorage.getItem(TOKEN_KEY);
  if (!token) {
    token = crypto.randomUUID();
    localStorage.setItem(TOKEN_KEY, token);
  }
  return token;
}

async function request(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: { "content-type": "application/json", "x-device-token": deviceToken() },
    body: body != null ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    let message = `server error ${res.status}`;
    try {
      const parsed = await res.json();
      if (parsed?.error) message = parsed.error;
    } catch {
      /* non-JSON error body */
    }
    throw new Error(message);
  }
  if (res.status === 204) return null;
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

export const api = {
  registerUser: (name) => request("POST", "/api/users", { deviceToken: deviceToken(), name }),
  me: () => request("GET", "/api/me"),
  listSegments: () => request("GET", "/api/segments"),
  createSegment: (name, activityType, polyline, distanceM) =>
    request("POST", "/api/segments", { name, activityType, polyline, distanceM }),
  listMyEfforts: (segmentId) => request("GET", `/api/segments/${segmentId}/efforts`),
  createEffort: (segmentId, startedAtMs, durationS, points) =>
    request("POST", "/api/efforts", { segmentId, startedAt: startedAtMs, durationS, points }),
  createChallenge: (effortId) => request("POST", "/api/challenges", { effortId }),
  challengeDetails: (token) => request("GET", `/api/challenges/${token}`),
  acceptChallenge: (token) => request("POST", `/api/challenges/${token}/accept`),
  completeChallenge: (token, startedAtMs, durationS, points) =>
    request("POST", `/api/challenges/${token}/result`, { startedAt: startedAtMs, durationS, points }),
  listRivals: () => request("GET", "/api/rivals"),
  createRace: (segmentId) => request("POST", "/api/races", segmentId ? { segmentId } : {}),
};
