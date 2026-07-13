import test from "node:test";
import assert from "node:assert/strict";
import { RaceRoom, type Peer, type ServerMsg } from "../src/race-room.js";

class FakePeer implements Peer {
  readonly inbox: ServerMsg[] = [];
  constructor(readonly userId: string, readonly name: string) {}
  send(msg: ServerMsg): void {
    this.inbox.push(msg);
  }
  last(type: ServerMsg["type"]): ServerMsg | undefined {
    return [...this.inbox].reverse().find((m) => m.type === type);
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

test("full race: join, ready, countdown, positions relayed, faster racer wins", async () => {
  const results: unknown[] = [];
  const room = new RaceRoom("race-1", null, {
    countdownMs: 20,
    onResult: (r) => results.push(r),
  });
  const chris = new FakePeer("u-chris", "Chris");
  const alex = new FakePeer("u-alex", "Alex");

  room.join(chris);
  room.join(alex);
  assert.equal(chris.last("peer_joined")?.type, "peer_joined");

  room.ready("u-chris");
  room.ready("u-alex");
  const countdownChris = chris.last("countdown");
  const countdownAlex = alex.last("countdown");
  assert.ok(countdownChris && countdownAlex);
  assert.equal(
    (countdownChris as { startAt: number }).startAt,
    (countdownAlex as { startAt: number }).startAt,
    "both racers must receive the identical start timestamp"
  );

  await sleep(30); // countdown elapses -> racing

  room.position("u-chris", 5, 42);
  const relayed = alex.last("pos");
  assert.deepEqual(relayed, { type: "pos", userId: "u-chris", t: 5, d: 42 });
  assert.equal(
    chris.inbox.filter((m) => m.type === "pos").length,
    0,
    "your own positions are not echoed back"
  );

  room.finish("u-alex", 118);
  room.finish("u-chris", 124);

  const result = chris.last("result") as Extract<ServerMsg, { type: "result" }>;
  assert.equal(result.winnerId, "u-alex");
  assert.equal(result.reason, "finish");
  assert.deepEqual(result.times, { "u-chris": 124, "u-alex": 118 });
  assert.equal(results.length, 1);
  assert.equal(room.state, "finished");
});

test("third racer is rejected", () => {
  const room = new RaceRoom("race-2", null, { countdownMs: 10 });
  room.join(new FakePeer("a", "A"));
  room.join(new FakePeer("b", "B"));
  const crasher = new FakePeer("c", "C");
  room.join(crasher);
  assert.equal(crasher.last("error")?.type, "error");
});

test("disconnect during race starts grace period; reconnect cancels it", async () => {
  const results: unknown[] = [];
  const room = new RaceRoom("race-3", null, {
    countdownMs: 10,
    graceMs: 60,
    onResult: (r) => results.push(r),
  });
  const a = new FakePeer("a", "A");
  const b = new FakePeer("b", "B");
  room.join(a);
  room.join(b);
  room.ready("a");
  room.ready("b");
  await sleep(15);

  room.disconnect("a");
  const notice = b.last("peer_disconnected") as Extract<ServerMsg, { type: "peer_disconnected" }>;
  assert.equal(notice.userId, "a");
  assert.equal(notice.graceMs, 60);

  const aAgain = new FakePeer("a", "A");
  room.join(aAgain); // same userId -> reconnect
  assert.equal(b.last("peer_reconnected")?.type, "peer_reconnected");
  assert.ok(aAgain.last("countdown"), "reconnecting racer is re-sent the start timestamp");

  await sleep(80); // past the original grace window
  assert.equal(room.state, "racing", "reconnect must cancel the DNF timer");
  assert.equal(results.length, 0);
});

test("disconnect grace expiry settles the race as a DNF win for the survivor", async () => {
  const results: Array<{ winnerId: string; reason: string }> = [];
  const room = new RaceRoom("race-4", null, {
    countdownMs: 10,
    graceMs: 30,
    onResult: (r) => results.push(r),
  });
  const a = new FakePeer("a", "A");
  const b = new FakePeer("b", "B");
  room.join(a);
  room.join(b);
  room.ready("a");
  room.ready("b");
  await sleep(15);

  room.disconnect("b");
  await sleep(50);

  assert.equal(room.state, "finished");
  assert.equal(results.length, 1);
  assert.equal(results[0]?.winnerId, "a");
  assert.equal(results[0]?.reason, "dnf");
  const result = a.last("result") as Extract<ServerMsg, { type: "result" }>;
  assert.equal(result.winnerId, "a");
  assert.equal(result.reason, "dnf");
});

test("leaving before the start just removes you from the roster", () => {
  const room = new RaceRoom("race-5", null, {});
  const a = new FakePeer("a", "A");
  const b = new FakePeer("b", "B");
  room.join(a);
  room.join(b);
  room.disconnect("a");
  assert.equal(b.last("peer_left")?.type, "peer_left");
  assert.equal(room.state, "waiting");
  // The slot is free again.
  const c = new FakePeer("c", "C");
  room.join(c);
  assert.equal(c.last("joined")?.type, "joined");
});
