import test from "node:test";
import assert from "node:assert/strict";
import { createGhostRaceServer, type GhostRaceServer } from "../src/server.js";

const POLYLINE = [
  { lat: 37.7749, lon: -122.4194 },
  { lat: 37.7762, lon: -122.4165 },
];

async function withServer(fn: (baseUrl: string, app: GhostRaceServer) => Promise<void>) {
  const app = createGhostRaceServer();
  const port = await app.listen(0);
  try {
    await fn(`http://127.0.0.1:${port}`, app);
  } finally {
    await app.close();
  }
}

async function api(
  baseUrl: string,
  method: string,
  path: string,
  opts: { token?: string; body?: unknown } = {}
): Promise<{ status: number; body: any }> {
  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      "content-type": "application/json",
      ...(opts.token ? { "x-device-token": opts.token } : {}),
    },
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  return { status: res.status, body: await res.json() };
}

test("health check needs no auth; everything else does", async () => {
  await withServer(async (base) => {
    const health = await api(base, "GET", "/api/health");
    assert.equal(health.status, 200);
    const denied = await api(base, "GET", "/api/segments");
    assert.equal(denied.status, 401);
  });
});

test("full ghost-challenge flow over HTTP: record, challenge, accept, race, rivalry", async () => {
  await withServer(async (base) => {
    // Chris and Alex register their devices.
    const chris = await api(base, "POST", "/api/users", {
      body: { deviceToken: "chris-phone", name: "Chris" },
    });
    const alex = await api(base, "POST", "/api/users", {
      body: { deviceToken: "alex-phone", name: "Alex" },
    });
    assert.equal(chris.status, 200);

    // Chris records a segment and an effort on it.
    const segment = await api(base, "POST", "/api/segments", {
      token: "chris-phone",
      body: { name: "River loop", activityType: "run", polyline: POLYLINE, distanceM: 1200 },
    });
    assert.equal(segment.status, 200);

    const effort = await api(base, "POST", "/api/efforts", {
      token: "chris-phone",
      body: {
        segmentId: segment.body.id,
        startedAt: Date.now(),
        durationS: 300,
        points: [
          { t: 0, d: 0 },
          { t: 300, d: 1200 },
        ],
      },
    });
    assert.equal(effort.status, 200);

    // Chris's efforts on the segment list fastest-first, only his own.
    const efforts = await api(base, "GET", `/api/segments/${segment.body.id}/efforts`, {
      token: "chris-phone",
    });
    assert.equal(efforts.status, 200);
    assert.equal(efforts.body.length, 1);
    assert.equal(efforts.body[0].durationS, 300);
    const alexEfforts = await api(base, "GET", `/api/segments/${segment.body.id}/efforts`, {
      token: "alex-phone",
    });
    assert.equal(alexEfforts.body.length, 0, "you only see your own efforts");

    // Chris creates a challenge; the response carries the shareable deep link.
    const challenge = await api(base, "POST", "/api/challenges", {
      token: "chris-phone",
      body: { effortId: effort.body.id },
    });
    assert.equal(challenge.status, 200);
    assert.match(challenge.body.url, /^ghostrace:\/\/challenge\//);

    // Alex opens the link: fetches challenge details (ghost + segment).
    const details = await api(base, "GET", `/api/challenges/${challenge.body.token}`, {
      token: "alex-phone",
    });
    assert.equal(details.status, 200);
    assert.equal(details.body.challengerName, "Chris");
    assert.equal(details.body.ghost.durationS, 300);
    assert.equal(details.body.segment.name, "River loop");

    const accepted = await api(base, "POST", `/api/challenges/${challenge.body.token}/accept`, {
      token: "alex-phone",
    });
    assert.equal(accepted.status, 200);
    assert.equal(accepted.body.status, "accepted");

    // Alex races the ghost and wins by 12 seconds.
    const outcome = await api(base, "POST", `/api/challenges/${challenge.body.token}/result`, {
      token: "alex-phone",
      body: {
        startedAt: Date.now(),
        durationS: 288,
        points: [
          { t: 0, d: 0 },
          { t: 288, d: 1200 },
        ],
      },
    });
    assert.equal(outcome.status, 200);
    assert.equal(outcome.body.result.winnerId, alex.body.id);

    // Both rivals see the head-to-head record.
    const chrisRivals = await api(base, "GET", "/api/rivals", { token: "chris-phone" });
    assert.equal(chrisRivals.body[0].rivalName, "Alex");
    assert.equal(chrisRivals.body[0].wins, 0);
    assert.equal(chrisRivals.body[0].losses, 1);
  });
});

test("validation: bad segment payloads are rejected", async () => {
  await withServer(async (base) => {
    await api(base, "POST", "/api/users", { body: { deviceToken: "t", name: "T" } });
    const badType = await api(base, "POST", "/api/segments", {
      token: "t",
      body: { name: "x", activityType: "swim", polyline: POLYLINE, distanceM: 100 },
    });
    assert.equal(badType.status, 400);
    const shortLine = await api(base, "POST", "/api/segments", {
      token: "t",
      body: { name: "x", activityType: "run", polyline: [POLYLINE[0]], distanceM: 100 },
    });
    assert.equal(shortLine.status, 400);
    const badDistance = await api(base, "POST", "/api/segments", {
      token: "t",
      body: { name: "x", activityType: "run", polyline: POLYLINE, distanceM: -5 },
    });
    assert.equal(badDistance.status, 400);
  });
});

test("race creation returns a room id usable by the WS layer", async () => {
  await withServer(async (base, app) => {
    await api(base, "POST", "/api/users", { body: { deviceToken: "t", name: "T" } });
    const race = await api(base, "POST", "/api/races", { token: "t", body: {} });
    assert.equal(race.status, 200);
    assert.ok(app.rooms.get(race.body.raceId), "room exists in the manager");
  });
});
