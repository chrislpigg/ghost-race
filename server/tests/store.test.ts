import test from "node:test";
import assert from "node:assert/strict";
import { openDb } from "../src/db.js";
import * as store from "../src/store.js";

const POLYLINE = [
  { lat: 37.7749, lon: -122.4194 },
  { lat: 37.7755, lon: -122.418 },
  { lat: 37.7762, lon: -122.4165 },
];

function seedUsers(db: ReturnType<typeof openDb>) {
  const chris = store.upsertUser(db, "chris-token", "Chris");
  const alex = store.upsertUser(db, "alex-token", "Alex");
  return { chris, alex };
}

test("upsertUser is idempotent by device token and updates the name", () => {
  const db = openDb();
  const first = store.upsertUser(db, "tok", "Chris");
  const again = store.upsertUser(db, "tok", "Chris");
  assert.equal(first.id, again.id);
  const renamed = store.upsertUser(db, "tok", "Christopher");
  assert.equal(renamed.id, first.id);
  assert.equal(store.getUserByToken(db, "tok")?.name, "Christopher");
});

test("segment and effort round-trip preserves geometry and points", () => {
  const db = openDb();
  const { chris } = seedUsers(db);
  const segment = store.createSegment(db, chris.id, {
    name: "River loop",
    activityType: "run",
    polyline: POLYLINE,
    distanceM: 1200,
  });
  const loaded = store.getSegment(db, segment.id);
  assert.deepEqual(loaded?.polyline, POLYLINE);
  assert.equal(loaded?.gateRadiusM, 25);

  const effort = store.createEffort(db, chris.id, {
    segmentId: segment.id,
    startedAt: 1700000000000,
    durationS: 300,
    points: [
      { t: 0, d: 0 },
      { t: 150, d: 600 },
      { t: 300, d: 1200 },
    ],
  });
  const loadedEffort = store.getEffort(db, effort.id);
  assert.equal(loadedEffort?.durationS, 300);
  assert.deepEqual(loadedEffort?.points.at(-1), { t: 300, d: 1200 });
});

test("challenge lifecycle: create -> accept -> complete records the right winner", () => {
  const db = openDb();
  const { chris, alex } = seedUsers(db);
  const segment = store.createSegment(db, chris.id, {
    name: "River loop",
    activityType: "run",
    polyline: POLYLINE,
    distanceM: 1200,
  });
  const ghost = store.createEffort(db, chris.id, {
    segmentId: segment.id,
    startedAt: 1,
    durationS: 300,
    points: [{ t: 0, d: 0 }, { t: 300, d: 1200 }],
  });

  const challenge = store.createChallenge(db, chris.id, ghost.id);
  assert.equal(challenge.status, "pending");
  assert.ok(challenge.token.length >= 8);

  store.acceptChallenge(db, challenge.token, alex.id);

  // Alex beats the ghost by 10 seconds.
  const outcome = store.completeChallenge(db, challenge.token, alex.id, {
    startedAt: 2,
    durationS: 290,
    points: [{ t: 0, d: 0 }, { t: 290, d: 1200 }],
  });
  assert.equal(outcome.challenge.status, "completed");
  assert.equal(outcome.result.winnerId, alex.id);
  assert.equal(outcome.result.loserId, chris.id);
  assert.equal(outcome.result.winnerTimeS, 290);
  assert.equal(outcome.result.loserTimeS, 300);
  assert.equal(outcome.result.mode, "ghost");
});

test("completing a challenge twice is rejected", () => {
  const db = openDb();
  const { chris, alex } = seedUsers(db);
  const segment = store.createSegment(db, chris.id, {
    name: "s",
    activityType: "ride",
    polyline: POLYLINE,
    distanceM: 1000,
  });
  const ghost = store.createEffort(db, chris.id, {
    segmentId: segment.id,
    startedAt: 1,
    durationS: 100,
    points: [{ t: 0, d: 0 }],
  });
  const challenge = store.createChallenge(db, chris.id, ghost.id);
  store.completeChallenge(db, challenge.token, alex.id, {
    startedAt: 2,
    durationS: 90,
    points: [{ t: 0, d: 0 }],
  });
  assert.throws(
    () =>
      store.completeChallenge(db, challenge.token, alex.id, {
        startedAt: 3,
        durationS: 80,
        points: [{ t: 0, d: 0 }],
      }),
    /already completed/
  );
});

test("challenger cannot accept their own challenge, strangers cannot steal a claimed one", () => {
  const db = openDb();
  const { chris, alex } = seedUsers(db);
  const mallory = store.upsertUser(db, "mallory-token", "Mallory");
  const segment = store.createSegment(db, chris.id, {
    name: "s",
    activityType: "run",
    polyline: POLYLINE,
    distanceM: 1000,
  });
  const ghost = store.createEffort(db, chris.id, {
    segmentId: segment.id,
    startedAt: 1,
    durationS: 100,
    points: [{ t: 0, d: 0 }],
  });
  const challenge = store.createChallenge(db, chris.id, ghost.id);
  assert.throws(() => store.acceptChallenge(db, challenge.token, chris.id), /own challenge/);
  store.acceptChallenge(db, challenge.token, alex.id);
  assert.throws(() => store.acceptChallenge(db, challenge.token, mallory.id), /claimed/);
});

test("rivalry record aggregates wins and losses per opponent", () => {
  const db = openDb();
  const { chris, alex } = seedUsers(db);
  store.recordResult(db, {
    mode: "ghost",
    winnerId: chris.id,
    loserId: alex.id,
    winnerTimeS: 100,
    loserTimeS: 110,
  });
  store.recordResult(db, {
    mode: "live",
    winnerId: chris.id,
    loserId: alex.id,
    winnerTimeS: 95,
    loserTimeS: 99,
  });
  store.recordResult(db, {
    mode: "ghost",
    winnerId: alex.id,
    loserId: chris.id,
    winnerTimeS: 90,
    loserTimeS: 101,
  });

  const rivals = store.listRivals(db, chris.id);
  assert.equal(rivals.length, 1);
  assert.equal(rivals[0]?.rivalName, "Alex");
  assert.equal(rivals[0]?.wins, 2);
  assert.equal(rivals[0]?.losses, 1);

  const alexView = store.listRivals(db, alex.id);
  assert.equal(alexView[0]?.wins, 1);
  assert.equal(alexView[0]?.losses, 2);
});
