export type ActivityType = "run" | "ride";

export interface LatLon {
  lat: number;
  lon: number;
}

/** One sample of an effort: seconds since start, meters along the segment. */
export interface EffortPoint {
  t: number;
  d: number;
}

export interface User {
  id: string;
  deviceToken: string;
  name: string;
  createdAt: number;
}

export interface Segment {
  id: string;
  ownerId: string;
  name: string;
  activityType: ActivityType;
  polyline: LatLon[];
  distanceM: number;
  gateRadiusM: number;
  createdAt: number;
}

export interface Effort {
  id: string;
  segmentId: string;
  userId: string;
  startedAt: number;
  durationS: number;
  points: EffortPoint[];
  createdAt: number;
}

export type ChallengeStatus = "pending" | "accepted" | "completed" | "declined";

export interface Challenge {
  id: string;
  token: string;
  segmentId: string;
  effortId: string;
  challengerId: string;
  inviteeId: string | null;
  status: ChallengeStatus;
  createdAt: number;
}

export type RaceMode = "ghost" | "live";
export type ResultReason = "finish" | "dnf";

export interface RaceResult {
  id: string;
  challengeId: string | null;
  segmentId: string | null;
  mode: RaceMode;
  winnerId: string;
  loserId: string;
  winnerTimeS: number | null;
  loserTimeS: number | null;
  reason: ResultReason;
  createdAt: number;
}

/** Head-to-head record against one rival, from the perspective of `userId`. */
export interface RivalRecord {
  rivalId: string;
  rivalName: string;
  wins: number;
  losses: number;
  lastRaceAt: number;
}
