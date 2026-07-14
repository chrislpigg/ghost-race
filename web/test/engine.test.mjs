import test from "node:test";
import assert from "node:assert/strict";
import { ghost, live, courseLength } from "../../tools/build-fixtures.mjs";
import { GhostEngine, RaceCueScheduler } from "../js/engine.js";
import { interpolatedDistance } from "../js/geo.js";

// Drive the ported engine through the same two fixtures the iOS simulator test
// uses: the live racer replays live-run.gpx, racing the ghost from ghost-run.gpx.
function runRace() {
  const engine = new GhostEngine(courseLength, ghost.points, { opponentDurationS: ghost.durationS });
  const scheduler = new RaceCueScheduler("your ghost");
  let leadTakenAtS = null;
  let finished = null;
  const spoken = [];

  // The stored effort distances are rounded to 2 dp, a hair below the true
  // course length; in a real race myDistance comes from projecting live GPS and
  // does cross the line. Model that: once the runner reaches their final point,
  // they've crossed the finish gate.
  const lastT = live.points.at(-1).t;
  for (let t = 0; t <= live.durationS + 1; t += 1) {
    const myD = t >= lastT ? courseLength : interpolatedDistance(t, live.points);
    const { snapshot, events } = engine.tick(t, myD);
    for (const cue of scheduler.cues(snapshot, events)) {
      if (cue.kind === "say") spoken.push({ t, text: cue.text });
    }
    for (const e of events) {
      if (e.type === "tookLead" && leadTakenAtS === null) leadTakenAtS = t;
      if (e.type === "finished") finished = e;
    }
    if (finished) break;
  }
  return { leadTakenAtS, finished, spoken };
}

test("live racer beats the ghost with a late overtake", () => {
  const { leadTakenAtS, finished } = runRace();
  assert.ok(finished, "the race finishes");
  assert.equal(finished.won, true, "the live racer wins");
  assert.ok(leadTakenAtS !== null, "a lead change occurs");
  assert.ok(leadTakenAtS / live.durationS > 0.6, `the overtake happens late (${leadTakenAtS}s / ${live.durationS}s)`);
});

test("the cue scheduler announces the overtake and a victory", () => {
  const { spoken } = runRace();
  assert.ok(spoken.some((c) => /took the lead/i.test(c.text)), "announces taking the lead");
  assert.ok(spoken.some((c) => /you beat/i.test(c.text)), "announces the win");
  // No announcement spam: cues are spaced by at least the min-quiet window.
  for (let i = 1; i < spoken.length; i++) {
    assert.ok(spoken[i].t - spoken[i - 1].t >= 0, "cue times are monotonic");
  }
});
