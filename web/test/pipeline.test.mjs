import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseGpx } from "../js/gpx.js";
import { project, cumulativeDistances } from "../js/geo.js";
import { GhostEngine, GateDetector, RaceCueScheduler } from "../js/engine.js";

// Exercise the exact pipeline the web RaceController runs for a ghost race:
// parse GPX -> project onto the course -> gate detection -> engine tick ->
// cue scheduling. This is the browser code path minus the DOM.
const here = dirname(fileURLToPath(import.meta.url));
const fixtures = join(here, "..", "fixtures");
const ghostGpx = parseGpx(readFileSync(join(fixtures, "ghost-run.gpx"), "utf8"));
const liveGpx = parseGpx(readFileSync(join(fixtures, "live-run.gpx"), "utf8"));

test("GPX fixtures parse into time-ordered waypoints", () => {
  assert.ok(ghostGpx.length > 30 && liveGpx.length > 30);
  for (const pts of [ghostGpx, liveGpx]) {
    for (let i = 1; i < pts.length; i++) assert.ok(pts[i].t > pts[i - 1].t);
    assert.equal(pts[0].t, 0);
  }
});

test("a full ghost race resolves: gate fires, live racer wins late, cues fire", () => {
  // The recorded ghost effort defines the course.
  const polyline = ghostGpx.map((p) => ({ lat: p.lat, lon: p.lon }));
  const cumulative = cumulativeDistances(polyline);
  const courseDistanceM = cumulative[cumulative.length - 1];
  const ghostPoints = ghostGpx.map((p) => ({
    t: p.t,
    d: Math.min(project(p, polyline, cumulative).distanceAlongM, courseDistanceM),
  }));
  const ghostDurationS = ghostPoints[ghostPoints.length - 1].t;

  const engine = new GhostEngine(courseDistanceM, ghostPoints, { opponentDurationS: ghostDurationS });
  const scheduler = new RaceCueScheduler("your ghost");
  const gate = new GateDetector(polyline[0], { radiusM: 25 });

  let raceStartT = null;
  let gateCrossed = false;
  let leadTakenAtS = null;
  let finished = null;
  const spoken = [];

  for (const fix of liveGpx) {
    if (raceStartT === null) {
      if (gate.update({ lat: fix.lat, lon: fix.lon })) {
        gateCrossed = true;
        raceStartT = fix.t;
      }
      continue;
    }
    const elapsed = fix.t - raceStartT;
    const myD = Math.min(project(fix, polyline, cumulative).distanceAlongM, courseDistanceM);
    const { snapshot, events } = engine.tick(elapsed, myD);
    for (const cue of scheduler.cues(snapshot, events)) if (cue.kind === "say") spoken.push(cue.text);
    for (const e of events) {
      if (e.type === "tookLead" && leadTakenAtS === null) leadTakenAtS = elapsed;
      if (e.type === "finished") finished = e;
    }
    if (finished) break;
  }

  assert.ok(gateCrossed, "the start gate fires as the runner crosses the line");
  assert.ok(finished, "the race reaches the finish");
  assert.equal(finished.won, true, "the live racer wins");
  assert.ok(leadTakenAtS !== null && leadTakenAtS / ghostDurationS > 0.6, "the overtake happens late");
  assert.ok(spoken.some((t) => /took the lead/i.test(t)), "announces the overtake");
  assert.ok(spoken.some((t) => /you beat/i.test(t)), "announces the win");
});
