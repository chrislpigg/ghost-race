import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { ghost, live, courseLength, crosscheck } from "./build-fixtures.mjs";
import { distanceM, interpolatedDistance, project } from "./geo.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

test("efforts are monotonic and finish exactly at the course length", () => {
  for (const effort of [ghost, live]) {
    for (let i = 1; i < effort.points.length; i++) {
      assert.ok(effort.points[i].t > effort.points[i - 1].t, "time strictly increases");
      assert.ok(effort.points[i].d >= effort.points[i - 1].d, "distance never decreases");
    }
    assert.equal(effort.points[0].d, 0);
    assert.ok(Math.abs(effort.points.at(-1).d - courseLength) < 0.01);
  }
});

test("the live racer beats the ghost, with the overtake in the final 40%", () => {
  assert.ok(live.durationS < ghost.durationS, "live must win");
  const { leadTakenAtS } = crosscheck.race;
  assert.ok(leadTakenAtS !== null, "lead change must occur");
  assert.ok(leadTakenAtS / live.durationS > 0.6, "overtake happens late for drama");
  // Before the overtake the live racer is genuinely behind.
  const midGap =
    interpolatedDistance(live.durationS * 0.4, live.points) -
    interpolatedDistance(live.durationS * 0.4, ghost.points);
  assert.ok(midGap < -3, `live racer should trail mid-race (gap ${midGap.toFixed(1)}m)`);
});

test("GPX fixtures parse, are time-ordered, and track the course geometry", () => {
  for (const file of ["ghost-run.gpx", "live-run.gpx"]) {
    const xml = readFileSync(join(root, "ios", "Fixtures", file), "utf8");
    const waypoints = [...xml.matchAll(/<wpt lat="([-\d.]+)" lon="([-\d.]+)">\s*<time>([^<]+)<\/time>/g)];
    assert.ok(waypoints.length > 30, `${file}: enough waypoints for smooth playback`);
    let prev = 0;
    for (const [, , , time] of waypoints) {
      const ms = Date.parse(time);
      assert.ok(ms > prev, `${file}: times strictly increase`);
      prev = ms;
    }
    // Every waypoint must project onto the course with a tiny offset.
    for (const [, lat, lon] of waypoints) {
      const { offsetM } = project({ lat: Number(lat), lon: Number(lon) }, crosscheck.course.polyline);
      assert.ok(offsetM < 1, `${file}: waypoint sits on the course (offset ${offsetM.toFixed(2)}m)`);
    }
    // First and last waypoints are the segment gates.
    const first = waypoints[0];
    const last = waypoints.at(-1);
    const start = crosscheck.course.polyline[0];
    const finish = crosscheck.course.polyline.at(-1);
    assert.ok(distanceM({ lat: +first[1], lon: +first[2] }, start) < 1);
    assert.ok(distanceM({ lat: +last[1], lon: +last[2] }, finish) < 1);
  }
});

test("crosscheck expected values are self-consistent with geo.mjs", () => {
  for (const { point, expected } of crosscheck.projectionCases) {
    const p = project(point, crosscheck.course.polyline);
    assert.ok(Math.abs(p.distanceAlongM - expected.distanceAlongM) < 0.01);
    assert.ok(Math.abs(p.offsetM - expected.offsetM) < 0.01);
  }
  for (const { t, expected } of crosscheck.interpolationCases) {
    assert.ok(Math.abs(interpolatedDistance(t, crosscheck.ghostEffort.points) - expected) < 0.01);
  }
});
