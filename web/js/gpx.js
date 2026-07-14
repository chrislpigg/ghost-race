/**
 * GPX parsing and position sources. A position source drives a recording or a
 * race by calling `onFix(coord, elapsedSeconds)` over time. Two implementations:
 * real device GPS, and GPX playback (for desktop testing, with a speed multiplier
 * so a 4-minute race can be watched in seconds — elapsed time stays in the
 * course's own seconds so audio cadence still lands correctly).
 */

/** Parse `<wpt>`/`<trkpt>` points with times into [{lat, lon, t}] (t = seconds from first). */
export function parseGpx(xml) {
  const points = [];
  const re =
    /<(?:wpt|trkpt)\s+lat="([-\d.]+)"\s+lon="([-\d.]+)"\s*>[\s\S]*?<time>([^<]+)<\/time>/g;
  let m;
  while ((m = re.exec(xml)) !== null) {
    points.push({ lat: Number(m[1]), lon: Number(m[2]), tMs: Date.parse(m[3]) });
  }
  if (points.length > 0) {
    const t0 = points[0].tMs;
    for (const p of points) p.t = (p.tMs - t0) / 1000;
  }
  return points;
}

/** Replays parsed GPX points, emitting each at its scaled wall-clock time. */
export class GpxPlaybackSource {
  constructor(points, { speed = 1 } = {}) {
    this.points = points;
    this.speed = speed;
    this.timers = [];
    this.onFix = null;
    this.onDone = null;
  }

  start() {
    for (const p of this.points) {
      const delayMs = (p.t * 1000) / this.speed;
      this.timers.push(
        setTimeout(() => this.onFix?.({ lat: p.lat, lon: p.lon }, p.t), delayMs),
      );
    }
    const lastT = this.points.length ? this.points[this.points.length - 1].t : 0;
    this.timers.push(setTimeout(() => this.onDone?.(), (lastT * 1000) / this.speed + 60));
  }

  stop() {
    for (const id of this.timers) clearTimeout(id);
    this.timers = [];
  }
}

/** Real device GPS via the Geolocation API. */
export class GeolocationSource {
  constructor() {
    this.watchId = null;
    this.onFix = null;
    this.startMs = null;
    this.latestAccuracy = null;
  }

  start() {
    if (!navigator.geolocation) throw new Error("This browser has no location access.");
    this.startMs = performance.now();
    this.watchId = navigator.geolocation.watchPosition(
      (pos) => {
        this.latestAccuracy = pos.coords.accuracy;
        const t = (performance.now() - this.startMs) / 1000;
        this.onFix?.(
          { lat: pos.coords.latitude, lon: pos.coords.longitude, accuracy: pos.coords.accuracy },
          t,
        );
      },
      (err) => console.warn("geolocation error", err),
      { enableHighAccuracy: true, maximumAge: 0, timeout: 15000 },
    );
  }

  stop() {
    if (this.watchId != null) navigator.geolocation.clearWatch(this.watchId);
    this.watchId = null;
  }
}

/** Fetch a bundled fixture (e.g. "ghost-run.gpx") and parse it. */
export async function loadFixture(name) {
  const res = await fetch(`fixtures/${name}`);
  if (!res.ok) throw new Error(`Couldn't load fixture ${name}`);
  return parseGpx(await res.text());
}
