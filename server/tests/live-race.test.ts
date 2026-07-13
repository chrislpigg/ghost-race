import test from "node:test";
import assert from "node:assert/strict";
import WebSocket from "ws";
import { createGhostRaceServer } from "../src/server.js";
import type { ServerMsg } from "../src/race-room.js";

/**
 * End-to-end live race: two real WebSocket clients replay scripted efforts at
 * different paces over a 400m course. Verifies countdown synchronization,
 * position relay in both directions, the correct winner, and persistence of
 * the head-to-head record.
 */

class RaceClient {
  private ws: WebSocket;
  readonly inbox: ServerMsg[] = [];
  private waiters: Array<{ type: string; resolve: (m: ServerMsg) => void }> = [];

  constructor(url: string, readonly label: string) {
    this.ws = new WebSocket(url);
    this.ws.on("message", (data) => {
      const msg = JSON.parse(String(data)) as ServerMsg;
      this.inbox.push(msg);
      this.waiters = this.waiters.filter((w) => {
        if (w.type === msg.type) {
          w.resolve(msg);
          return false;
        }
        return true;
      });
    });
  }

  opened(): Promise<void> {
    if (this.ws.readyState === WebSocket.OPEN) return Promise.resolve();
    return new Promise((resolve, reject) => {
      this.ws.once("open", resolve);
      this.ws.once("error", reject);
    });
  }

  send(msg: unknown): void {
    this.ws.send(JSON.stringify(msg));
  }

  /** Resolve with the next (or an already received) message of `type`. */
  next<T extends ServerMsg["type"]>(type: T): Promise<Extract<ServerMsg, { type: T }>> {
    const already = this.inbox.find((m) => m.type === type);
    if (already) return Promise.resolve(already as Extract<ServerMsg, { type: T }>);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`${this.label}: timed out waiting for '${type}'`)),
        5000
      );
      this.waiters.push({
        type,
        resolve: (m) => {
          clearTimeout(timer);
          resolve(m as Extract<ServerMsg, { type: T }>);
        },
      });
    });
  }

  close(): void {
    this.ws.close();
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

test("scripted two-client live race: sync, relay, winner, persisted rivalry", async () => {
  const app = createGhostRaceServer({ race: { countdownMs: 60, graceMs: 200 } });
  const port = await app.listen(0);
  const base = `http://127.0.0.1:${port}`;

  try {
    // Register both racers and create the race room over REST.
    for (const [token, name] of [
      ["chris-phone", "Chris"],
      ["alex-phone", "Alex"],
    ] as const) {
      await fetch(`${base}/api/users`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ deviceToken: token, name }),
      });
    }
    const raceRes = await fetch(`${base}/api/races`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-device-token": "chris-phone" },
      body: JSON.stringify({}),
    });
    const { raceId } = (await raceRes.json()) as { raceId: string };

    const chris = new RaceClient(`ws://127.0.0.1:${port}/ws`, "chris");
    const alex = new RaceClient(`ws://127.0.0.1:${port}/ws`, "alex");
    await Promise.all([chris.opened(), alex.opened()]);

    chris.send({ type: "join", raceId, deviceToken: "chris-phone" });
    await chris.next("joined");
    alex.send({ type: "join", raceId, deviceToken: "alex-phone" });
    await alex.next("joined");
    await chris.next("peer_joined");

    chris.send({ type: "ready" });
    alex.send({ type: "ready" });

    // Countdown sync: both clients must receive the identical startAt.
    const [cdChris, cdAlex] = await Promise.all([chris.next("countdown"), alex.next("countdown")]);
    assert.equal(cdChris.startAt, cdAlex.startAt);
    assert.ok(cdChris.startAt > cdChris.serverNow, "start is in the future");

    await sleep(80); // let the countdown elapse

    // Scripted efforts over a 400m course, 4 ticks each.
    // Alex runs 5 m/s (finishes 400m in 80s), Chris runs 4 m/s (100s).
    for (let tick = 1; tick <= 4; tick++) {
      chris.send({ type: "pos", t: tick * 25, d: tick * 100 }); // 4 m/s
      alex.send({ type: "pos", t: tick * 20, d: tick * 100 }); // 5 m/s
      await sleep(5);
    }

    // Each side sees the other's positions, never its own.
    const chrisSeen = chris.inbox.filter((m) => m.type === "pos") as Array<
      Extract<ServerMsg, { type: "pos" }>
    >;
    const alexSeen = alex.inbox.filter((m) => m.type === "pos") as Array<
      Extract<ServerMsg, { type: "pos" }>
    >;
    assert.equal(chrisSeen.length, 4);
    assert.equal(alexSeen.length, 4);
    assert.deepEqual(
      chrisSeen.map((m) => [m.t, m.d]),
      [
        [20, 100],
        [40, 200],
        [60, 300],
        [80, 400],
      ],
      "Chris sees Alex's exact scripted track"
    );
    assert.deepEqual(
      alexSeen.map((m) => [m.t, m.d]),
      [
        [25, 100],
        [50, 200],
        [75, 300],
        [100, 400],
      ],
      "Alex sees Chris's exact scripted track"
    );

    alex.send({ type: "finish", durationS: 80 });
    await chris.next("peer_finished");
    chris.send({ type: "finish", durationS: 100 });

    const [resChris, resAlex] = await Promise.all([chris.next("result"), alex.next("result")]);
    assert.equal(resChris.reason, "finish");
    assert.deepEqual(resChris, resAlex);

    // The winner is Alex; confirm identity via the REST rivalry record.
    const rivalsRes = await fetch(`${base}/api/rivals`, {
      headers: { "x-device-token": "alex-phone" },
    });
    const rivals = (await rivalsRes.json()) as Array<{
      rivalName: string;
      wins: number;
      losses: number;
    }>;
    assert.equal(rivals.length, 1);
    assert.equal(rivals[0]?.rivalName, "Chris");
    assert.equal(rivals[0]?.wins, 1);
    assert.equal(rivals[0]?.losses, 0);

    chris.close();
    alex.close();
  } finally {
    await app.close();
  }
});

test("mid-race disconnect past grace records a DNF result", async () => {
  const app = createGhostRaceServer({ race: { countdownMs: 30, graceMs: 60 } });
  const port = await app.listen(0);
  const base = `http://127.0.0.1:${port}`;

  try {
    for (const [token, name] of [
      ["a-tok", "A"],
      ["b-tok", "B"],
    ] as const) {
      await fetch(`${base}/api/users`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ deviceToken: token, name }),
      });
    }
    const raceRes = await fetch(`${base}/api/races`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-device-token": "a-tok" },
      body: JSON.stringify({}),
    });
    const { raceId } = (await raceRes.json()) as { raceId: string };

    const a = new RaceClient(`ws://127.0.0.1:${port}/ws`, "a");
    const b = new RaceClient(`ws://127.0.0.1:${port}/ws`, "b");
    await Promise.all([a.opened(), b.opened()]);
    a.send({ type: "join", raceId, deviceToken: "a-tok" });
    await a.next("joined");
    b.send({ type: "join", raceId, deviceToken: "b-tok" });
    await b.next("joined");
    a.send({ type: "ready" });
    b.send({ type: "ready" });
    await Promise.all([a.next("countdown"), b.next("countdown")]);
    await sleep(40);

    b.close(); // B's phone dies mid-race
    const notice = await a.next("peer_disconnected");
    assert.equal(notice.graceMs, 60);

    const result = await a.next("result");
    assert.equal(result.reason, "dnf");

    const rivalsRes = await fetch(`${base}/api/rivals`, {
      headers: { "x-device-token": "a-tok" },
    });
    const rivals = (await rivalsRes.json()) as Array<{ wins: number }>;
    assert.equal(rivals[0]?.wins, 1);

    a.close();
  } finally {
    await app.close();
  }
});
