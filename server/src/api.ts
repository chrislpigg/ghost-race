import type { IncomingMessage, ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import type { Db } from "./db.js";
import * as store from "./store.js";
import { StoreError } from "./store.js";
import type { RaceRoomManager } from "./race-room.js";
import type { User } from "./types.js";

interface Ctx {
  db: Db;
  rooms: RaceRoomManager;
  user: User | null;
  params: Record<string, string>;
  body: unknown;
}

interface ApiResponse {
  status: number;
  body: unknown;
}

type Handler = (ctx: Ctx) => ApiResponse;

interface Route {
  method: string;
  segments: string[]; // ":name" marks a parameter
  handler: Handler;
  requiresAuth: boolean;
}

const routes: Route[] = [];

function route(method: string, pattern: string, handler: Handler, requiresAuth = true) {
  routes.push({ method, segments: pattern.split("/").filter(Boolean), handler, requiresAuth });
}

function ok(body: unknown): ApiResponse {
  return { status: 200, body };
}

function fail(status: number, message: string): ApiResponse {
  return { status, body: { error: message } };
}

function asRecord(body: unknown): Record<string, unknown> {
  if (typeof body !== "object" || body === null) throw new StoreError("invalid JSON body", 400);
  return body as Record<string, unknown>;
}

// -- routes ---------------------------------------------------------------

route("GET", "/api/health", () => ok({ ok: true }), false);

route(
  "POST",
  "/api/users",
  ({ db, body }) => {
    const b = asRecord(body);
    const deviceToken = String(b.deviceToken ?? "");
    const name = String(b.name ?? "").trim();
    if (!deviceToken || !name) return fail(400, "deviceToken and name are required");
    return ok(store.upsertUser(db, deviceToken, name));
  },
  false
);

route("GET", "/api/me", ({ user }) => ok(user));

route("POST", "/api/segments", ({ db, user, body }) => {
  const b = asRecord(body);
  const polyline = b.polyline;
  const activityType = b.activityType;
  if (activityType !== "run" && activityType !== "ride") {
    return fail(400, "activityType must be 'run' or 'ride'");
  }
  if (!Array.isArray(polyline) || polyline.length < 2) {
    return fail(400, "polyline must contain at least 2 points");
  }
  const distanceM = Number(b.distanceM);
  if (!Number.isFinite(distanceM) || distanceM <= 0) {
    return fail(400, "distanceM must be a positive number");
  }
  return ok(
    store.createSegment(db, user!.id, {
      name: String(b.name ?? "Unnamed segment"),
      activityType,
      polyline: polyline as { lat: number; lon: number }[],
      distanceM,
      gateRadiusM: b.gateRadiusM ? Number(b.gateRadiusM) : undefined,
    })
  );
});

route("GET", "/api/segments", ({ db, user }) => ok(store.listSegmentsByOwner(db, user!.id)));

route("GET", "/api/segments/:id", ({ db, params }) => {
  const segment = store.getSegment(db, params.id!);
  return segment ? ok(segment) : fail(404, "segment not found");
});

route("GET", "/api/segments/:id/efforts", ({ db, user, params }) => {
  if (!store.getSegment(db, params.id!)) return fail(404, "segment not found");
  // Fastest first; `?mine=1` filtering is implicit — MVP only ever returns
  // the caller's efforts to keep ghosts private until shared via challenge.
  return ok(store.listEffortsBySegment(db, params.id!, user!.id));
});

route("POST", "/api/efforts", ({ db, user, body }) => {
  const b = asRecord(body);
  const segmentId = String(b.segmentId ?? "");
  if (!store.getSegment(db, segmentId)) return fail(404, "segment not found");
  const points = b.points;
  if (!Array.isArray(points) || points.length === 0) {
    return fail(400, "points must be a non-empty array of {t, d}");
  }
  const durationS = Number(b.durationS);
  if (!Number.isFinite(durationS) || durationS <= 0) {
    return fail(400, "durationS must be a positive number");
  }
  return ok(
    store.createEffort(db, user!.id, {
      segmentId,
      startedAt: Number(b.startedAt) || Date.now(),
      durationS,
      points: points as { t: number; d: number }[],
    })
  );
});

route("GET", "/api/efforts/:id", ({ db, params }) => {
  const effort = store.getEffort(db, params.id!);
  return effort ? ok(effort) : fail(404, "effort not found");
});

route("POST", "/api/challenges", ({ db, user, body }) => {
  const b = asRecord(body);
  const challenge = store.createChallenge(db, user!.id, String(b.effortId ?? ""));
  return ok({ ...challenge, url: `ghostrace://challenge/${challenge.token}` });
});

route("GET", "/api/challenges/:token", ({ db, params }) => {
  const challenge = store.getChallengeByToken(db, params.token!);
  if (!challenge) return fail(404, "challenge not found");
  const effort = store.getEffort(db, challenge.effortId);
  const segment = store.getSegment(db, challenge.segmentId);
  const challenger = store.getUser(db, challenge.challengerId);
  return ok({ challenge, ghost: effort, segment, challengerName: challenger?.name ?? "Unknown" });
});

route("POST", "/api/challenges/:token/accept", ({ db, user, params }) =>
  ok(store.acceptChallenge(db, params.token!, user!.id))
);

route("POST", "/api/challenges/:token/result", ({ db, user, params, body }) => {
  const b = asRecord(body);
  const points = Array.isArray(b.points) ? (b.points as { t: number; d: number }[]) : [];
  const durationS = Number(b.durationS);
  if (!Number.isFinite(durationS) || durationS <= 0) {
    return fail(400, "durationS must be a positive number");
  }
  const outcome = store.completeChallenge(db, params.token!, user!.id, {
    startedAt: Number(b.startedAt) || Date.now(),
    durationS,
    points,
  });
  return ok(outcome);
});

route("GET", "/api/rivals", ({ db, user }) => ok(store.listRivals(db, user!.id)));

route("POST", "/api/races", ({ db, rooms, body }) => {
  const b = asRecord(body);
  const segmentId = b.segmentId ? String(b.segmentId) : null;
  if (segmentId && !store.getSegment(db, segmentId)) return fail(404, "segment not found");
  const raceId = randomUUID();
  rooms.create(raceId, segmentId, (result) => {
    store.recordResult(db, {
      segmentId,
      mode: "live",
      winnerId: result.winnerId,
      loserId: result.loserId,
      winnerTimeS: result.winnerTimeS,
      loserTimeS: result.loserTimeS,
      reason: result.reason,
    });
  });
  return ok({ raceId });
});

// -- dispatcher -----------------------------------------------------------

function matchRoute(method: string, path: string): { route: Route; params: Record<string, string> } | null {
  const parts = path.split("/").filter(Boolean);
  for (const r of routes) {
    if (r.method !== method || r.segments.length !== parts.length) continue;
    const params: Record<string, string> = {};
    let matched = true;
    for (let i = 0; i < parts.length; i++) {
      const seg = r.segments[i]!;
      const part = parts[i]!;
      if (seg.startsWith(":")) params[seg.slice(1)] = decodeURIComponent(part);
      else if (seg !== part) {
        matched = false;
        break;
      }
    }
    if (matched) return { route: r, params };
  }
  return null;
}

async function readBody(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  if (chunks.length === 0) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new StoreError("invalid JSON body", 400);
  }
}

export function createRequestHandler(db: Db, rooms: RaceRoomManager) {
  return async (req: IncomingMessage, res: ServerResponse): Promise<void> => {
    const url = new URL(req.url ?? "/", "http://localhost");
    const found = matchRoute(req.method ?? "GET", url.pathname);
    let response: ApiResponse;
    if (!found) {
      response = fail(404, "not found");
    } else {
      try {
        const body = await readBody(req);
        let user: User | null = null;
        if (found.route.requiresAuth) {
          const token = req.headers["x-device-token"];
          user = typeof token === "string" ? store.getUserByToken(db, token) : null;
          if (!user) {
            respond(res, fail(401, "register via POST /api/users and send x-device-token"));
            return;
          }
        }
        response = found.route.handler({ db, rooms, user, params: found.params, body });
      } catch (err) {
        if (err instanceof StoreError) response = fail(err.status, err.message);
        else {
          console.error(err);
          response = fail(500, "internal error");
        }
      }
    }
    respond(res, response);
  };
}

function respond(res: ServerResponse, r: ApiResponse): void {
  const payload = JSON.stringify(r.body);
  res.writeHead(r.status, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(payload),
  });
  res.end(payload);
}
