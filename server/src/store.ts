import { randomUUID, randomBytes } from "node:crypto";
import type { Db } from "./db.js";
import type {
  ActivityType,
  Challenge,
  ChallengeStatus,
  Effort,
  EffortPoint,
  LatLon,
  RaceMode,
  RaceResult,
  ResultReason,
  RivalRecord,
  Segment,
  User,
} from "./types.js";

const now = () => Date.now();

// -- users --------------------------------------------------------------

export function upsertUser(db: Db, deviceToken: string, name: string): User {
  const existing = getUserByToken(db, deviceToken);
  if (existing) {
    if (name && name !== existing.name) {
      db.prepare("UPDATE users SET name = ? WHERE id = ?").run(name, existing.id);
      return { ...existing, name };
    }
    return existing;
  }
  const user: User = { id: randomUUID(), deviceToken, name, createdAt: now() };
  db.prepare(
    "INSERT INTO users (id, device_token, name, created_at) VALUES (?, ?, ?, ?)"
  ).run(user.id, user.deviceToken, user.name, user.createdAt);
  return user;
}

export function getUserByToken(db: Db, deviceToken: string): User | null {
  const row = db
    .prepare("SELECT * FROM users WHERE device_token = ?")
    .get(deviceToken) as UserRow | undefined;
  return row ? userFromRow(row) : null;
}

export function getUser(db: Db, id: string): User | null {
  const row = db.prepare("SELECT * FROM users WHERE id = ?").get(id) as UserRow | undefined;
  return row ? userFromRow(row) : null;
}

interface UserRow {
  id: string;
  device_token: string;
  name: string;
  created_at: number;
}

function userFromRow(r: UserRow): User {
  return { id: r.id, deviceToken: r.device_token, name: r.name, createdAt: r.created_at };
}

// -- segments -----------------------------------------------------------

export interface NewSegment {
  name: string;
  activityType: ActivityType;
  polyline: LatLon[];
  distanceM: number;
  gateRadiusM?: number;
}

export function createSegment(db: Db, ownerId: string, s: NewSegment): Segment {
  const segment: Segment = {
    id: randomUUID(),
    ownerId,
    name: s.name,
    activityType: s.activityType,
    polyline: s.polyline,
    distanceM: s.distanceM,
    gateRadiusM: s.gateRadiusM ?? 25,
    createdAt: now(),
  };
  db.prepare(
    `INSERT INTO segments (id, owner_id, name, activity_type, polyline, distance_m, gate_radius_m, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    segment.id,
    segment.ownerId,
    segment.name,
    segment.activityType,
    JSON.stringify(segment.polyline),
    segment.distanceM,
    segment.gateRadiusM,
    segment.createdAt
  );
  return segment;
}

export function getSegment(db: Db, id: string): Segment | null {
  const row = db.prepare("SELECT * FROM segments WHERE id = ?").get(id) as
    | SegmentRow
    | undefined;
  return row ? segmentFromRow(row) : null;
}

export function listSegmentsByOwner(db: Db, ownerId: string): Segment[] {
  const rows = db
    .prepare("SELECT * FROM segments WHERE owner_id = ? ORDER BY created_at DESC")
    .all(ownerId) as SegmentRow[];
  return rows.map(segmentFromRow);
}

interface SegmentRow {
  id: string;
  owner_id: string;
  name: string;
  activity_type: ActivityType;
  polyline: string;
  distance_m: number;
  gate_radius_m: number;
  created_at: number;
}

function segmentFromRow(r: SegmentRow): Segment {
  return {
    id: r.id,
    ownerId: r.owner_id,
    name: r.name,
    activityType: r.activity_type,
    polyline: JSON.parse(r.polyline) as LatLon[],
    distanceM: r.distance_m,
    gateRadiusM: r.gate_radius_m,
    createdAt: r.created_at,
  };
}

// -- efforts ------------------------------------------------------------

export interface NewEffort {
  segmentId: string;
  startedAt: number;
  durationS: number;
  points: EffortPoint[];
}

export function createEffort(db: Db, userId: string, e: NewEffort): Effort {
  const effort: Effort = {
    id: randomUUID(),
    segmentId: e.segmentId,
    userId,
    startedAt: e.startedAt,
    durationS: e.durationS,
    points: e.points,
    createdAt: now(),
  };
  db.prepare(
    `INSERT INTO efforts (id, segment_id, user_id, started_at, duration_s, points, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(
    effort.id,
    effort.segmentId,
    effort.userId,
    effort.startedAt,
    effort.durationS,
    JSON.stringify(effort.points),
    effort.createdAt
  );
  return effort;
}

export function listEffortsBySegment(db: Db, segmentId: string, userId?: string): Effort[] {
  const rows = (
    userId
      ? db
          .prepare(
            "SELECT * FROM efforts WHERE segment_id = ? AND user_id = ? ORDER BY duration_s ASC"
          )
          .all(segmentId, userId)
      : db
          .prepare("SELECT * FROM efforts WHERE segment_id = ? ORDER BY duration_s ASC")
          .all(segmentId)
  ) as EffortRow[];
  return rows.map(effortFromRow);
}

export function getEffort(db: Db, id: string): Effort | null {
  const row = db.prepare("SELECT * FROM efforts WHERE id = ?").get(id) as
    | EffortRow
    | undefined;
  return row ? effortFromRow(row) : null;
}

interface EffortRow {
  id: string;
  segment_id: string;
  user_id: string;
  started_at: number;
  duration_s: number;
  points: string;
  created_at: number;
}

function effortFromRow(r: EffortRow): Effort {
  return {
    id: r.id,
    segmentId: r.segment_id,
    userId: r.user_id,
    startedAt: r.started_at,
    durationS: r.duration_s,
    points: JSON.parse(r.points) as EffortPoint[],
    createdAt: r.created_at,
  };
}

// -- challenges ---------------------------------------------------------

export function createChallenge(db: Db, challengerId: string, effortId: string): Challenge {
  const effort = getEffort(db, effortId);
  if (!effort) throw new StoreError("effort not found", 404);
  if (effort.userId !== challengerId) {
    throw new StoreError("can only challenge with your own effort", 403);
  }
  const challenge: Challenge = {
    id: randomUUID(),
    token: randomBytes(8).toString("base64url"),
    segmentId: effort.segmentId,
    effortId,
    challengerId,
    inviteeId: null,
    status: "pending",
    createdAt: now(),
  };
  db.prepare(
    `INSERT INTO challenges (id, token, segment_id, effort_id, challenger_id, invitee_id, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    challenge.id,
    challenge.token,
    challenge.segmentId,
    challenge.effortId,
    challenge.challengerId,
    null,
    challenge.status,
    challenge.createdAt
  );
  return challenge;
}

export function getChallengeByToken(db: Db, token: string): Challenge | null {
  const row = db.prepare("SELECT * FROM challenges WHERE token = ?").get(token) as
    | ChallengeRow
    | undefined;
  return row ? challengeFromRow(row) : null;
}

export function acceptChallenge(db: Db, token: string, inviteeId: string): Challenge {
  const challenge = getChallengeByToken(db, token);
  if (!challenge) throw new StoreError("challenge not found", 404);
  if (challenge.challengerId === inviteeId) {
    throw new StoreError("cannot accept your own challenge", 409);
  }
  if (challenge.status === "completed") {
    throw new StoreError("challenge already completed", 409);
  }
  if (challenge.inviteeId && challenge.inviteeId !== inviteeId) {
    throw new StoreError("challenge already claimed by someone else", 409);
  }
  db.prepare("UPDATE challenges SET invitee_id = ?, status = 'accepted' WHERE id = ?").run(
    inviteeId,
    challenge.id
  );
  return { ...challenge, inviteeId, status: "accepted" };
}

/**
 * The invitee finished racing the ghost: store their effort, decide the
 * winner by elapsed time, and record the head-to-head result.
 */
export function completeChallenge(
  db: Db,
  token: string,
  inviteeId: string,
  inviteeEffort: { startedAt: number; durationS: number; points: EffortPoint[] }
): { challenge: Challenge; result: RaceResult; effort: Effort } {
  const challenge = getChallengeByToken(db, token);
  if (!challenge) throw new StoreError("challenge not found", 404);
  if (challenge.status === "completed") {
    throw new StoreError("challenge already completed", 409);
  }
  if (challenge.inviteeId && challenge.inviteeId !== inviteeId) {
    throw new StoreError("challenge belongs to someone else", 409);
  }
  const ghostEffort = getEffort(db, challenge.effortId);
  if (!ghostEffort) throw new StoreError("ghost effort missing", 500);

  const effort = createEffort(db, inviteeId, {
    segmentId: challenge.segmentId,
    startedAt: inviteeEffort.startedAt,
    durationS: inviteeEffort.durationS,
    points: inviteeEffort.points,
  });

  const inviteeWon = inviteeEffort.durationS < ghostEffort.durationS;
  const result = recordResult(db, {
    challengeId: challenge.id,
    segmentId: challenge.segmentId,
    mode: "ghost",
    winnerId: inviteeWon ? inviteeId : challenge.challengerId,
    loserId: inviteeWon ? challenge.challengerId : inviteeId,
    winnerTimeS: inviteeWon ? inviteeEffort.durationS : ghostEffort.durationS,
    loserTimeS: inviteeWon ? ghostEffort.durationS : inviteeEffort.durationS,
    reason: "finish",
  });

  db.prepare("UPDATE challenges SET invitee_id = ?, status = 'completed' WHERE id = ?").run(
    inviteeId,
    challenge.id
  );
  return {
    challenge: { ...challenge, inviteeId, status: "completed" as ChallengeStatus },
    result,
    effort,
  };
}

interface ChallengeRow {
  id: string;
  token: string;
  segment_id: string;
  effort_id: string;
  challenger_id: string;
  invitee_id: string | null;
  status: ChallengeStatus;
  created_at: number;
}

function challengeFromRow(r: ChallengeRow): Challenge {
  return {
    id: r.id,
    token: r.token,
    segmentId: r.segment_id,
    effortId: r.effort_id,
    challengerId: r.challenger_id,
    inviteeId: r.invitee_id,
    status: r.status,
    createdAt: r.created_at,
  };
}

// -- results / rivalries ------------------------------------------------

export interface NewResult {
  challengeId?: string | null;
  segmentId?: string | null;
  mode: RaceMode;
  winnerId: string;
  loserId: string;
  winnerTimeS: number | null;
  loserTimeS: number | null;
  reason?: ResultReason;
}

export function recordResult(db: Db, r: NewResult): RaceResult {
  const result: RaceResult = {
    id: randomUUID(),
    challengeId: r.challengeId ?? null,
    segmentId: r.segmentId ?? null,
    mode: r.mode,
    winnerId: r.winnerId,
    loserId: r.loserId,
    winnerTimeS: r.winnerTimeS,
    loserTimeS: r.loserTimeS,
    reason: r.reason ?? "finish",
    createdAt: now(),
  };
  db.prepare(
    `INSERT INTO results (id, challenge_id, segment_id, mode, winner_id, loser_id, winner_time_s, loser_time_s, reason, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    result.id,
    result.challengeId,
    result.segmentId,
    result.mode,
    result.winnerId,
    result.loserId,
    result.winnerTimeS,
    result.loserTimeS,
    result.reason,
    result.createdAt
  );
  return result;
}

export function listRivals(db: Db, userId: string): RivalRecord[] {
  const rows = db
    .prepare(
      `SELECT
         CASE WHEN winner_id = ? THEN loser_id ELSE winner_id END AS rival_id,
         SUM(CASE WHEN winner_id = ? THEN 1 ELSE 0 END) AS wins,
         SUM(CASE WHEN loser_id = ? THEN 1 ELSE 0 END) AS losses,
         MAX(created_at) AS last_race_at
       FROM results
       WHERE winner_id = ? OR loser_id = ?
       GROUP BY rival_id
       ORDER BY last_race_at DESC`
    )
    .all(userId, userId, userId, userId, userId) as Array<{
    rival_id: string;
    wins: number;
    losses: number;
    last_race_at: number;
  }>;
  return rows.map((r) => ({
    rivalId: r.rival_id,
    rivalName: getUser(db, r.rival_id)?.name ?? "Unknown",
    wins: r.wins,
    losses: r.losses,
    lastRaceAt: r.last_race_at,
  }));
}

// -- errors -------------------------------------------------------------

export class StoreError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = "StoreError";
  }
}
