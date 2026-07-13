import Database from "better-sqlite3";

export type Db = Database.Database;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  device_token  TEXT NOT NULL UNIQUE,
  name          TEXT NOT NULL,
  created_at    INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS segments (
  id             TEXT PRIMARY KEY,
  owner_id       TEXT NOT NULL REFERENCES users(id),
  name           TEXT NOT NULL,
  activity_type  TEXT NOT NULL CHECK (activity_type IN ('run', 'ride')),
  polyline       TEXT NOT NULL,
  distance_m     REAL NOT NULL,
  gate_radius_m  REAL NOT NULL DEFAULT 25,
  created_at     INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS efforts (
  id          TEXT PRIMARY KEY,
  segment_id  TEXT NOT NULL REFERENCES segments(id),
  user_id     TEXT NOT NULL REFERENCES users(id),
  started_at  INTEGER NOT NULL,
  duration_s  REAL NOT NULL,
  points      TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS challenges (
  id             TEXT PRIMARY KEY,
  token          TEXT NOT NULL UNIQUE,
  segment_id     TEXT NOT NULL REFERENCES segments(id),
  effort_id      TEXT NOT NULL REFERENCES efforts(id),
  challenger_id  TEXT NOT NULL REFERENCES users(id),
  invitee_id     TEXT REFERENCES users(id),
  status         TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'accepted', 'completed', 'declined')),
  created_at     INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS results (
  id            TEXT PRIMARY KEY,
  challenge_id  TEXT REFERENCES challenges(id),
  segment_id    TEXT REFERENCES segments(id),
  mode          TEXT NOT NULL CHECK (mode IN ('ghost', 'live')),
  winner_id     TEXT NOT NULL REFERENCES users(id),
  loser_id      TEXT NOT NULL REFERENCES users(id),
  winner_time_s REAL,
  loser_time_s  REAL,
  reason        TEXT NOT NULL DEFAULT 'finish' CHECK (reason IN ('finish', 'dnf')),
  created_at    INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_segments_owner ON segments(owner_id);
CREATE INDEX IF NOT EXISTS idx_efforts_segment ON efforts(segment_id);
CREATE INDEX IF NOT EXISTS idx_results_users ON results(winner_id, loser_id);
`;

export function openDb(path = ":memory:"): Db {
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.exec(SCHEMA);
  return db;
}
