import test from "node:test";
import assert from "node:assert/strict";
import { crosscheck } from "../../tools/build-fixtures.mjs";
import { project, interpolatedDistance } from "../js/geo.js";

// The web geo module is a third implementation of the same math (alongside
// Geo.swift and tools/geo.mjs). Pin it to the same shared fixture so a change
// on the web side that drifts from the others fails loudly.

test("web geo.js reproduces the shared crosscheck projection values", () => {
  for (const { point, expected } of crosscheck.projectionCases) {
    const p = project(point, crosscheck.course.polyline);
    assert.ok(Math.abs(p.distanceAlongM - expected.distanceAlongM) < 0.01, "distanceAlongM matches");
    assert.ok(Math.abs(p.offsetM - expected.offsetM) < 0.01, "offsetM matches");
  }
});

test("web geo.js reproduces the shared crosscheck interpolation values", () => {
  for (const { t, expected } of crosscheck.interpolationCases) {
    const got = interpolatedDistance(t, crosscheck.ghostEffort.points);
    assert.ok(Math.abs(got - expected) < 0.01, `interpolatedDistance(${t}) matches`);
  }
});
