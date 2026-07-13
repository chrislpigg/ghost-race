/**
 * JS twin of GhostRaceKit's Geo.swift and GhostEngine.interpolatedDistance.
 * The Swift code cannot be compiled in every environment GhostRace is
 * developed in, so this module implements the identical algorithms and the
 * shared `crosscheck.json` fixture pins both implementations to the same
 * expected values. If you change one, change the other.
 */

export const EARTH_RADIUS_M = 6_371_000;

const rad = (deg) => (deg * Math.PI) / 180;

/** Great-circle (haversine) distance in meters. */
export function distanceM(a, b) {
  const dLat = rad(b.lat - a.lat);
  const dLon = rad(b.lon - a.lon);
  const lat1 = rad(a.lat);
  const lat2 = rad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Cumulative meters at each polyline vertex; first 0, last = total length. */
export function cumulativeDistances(polyline) {
  const out = [];
  let total = 0;
  for (let i = 0; i < polyline.length; i++) {
    if (i > 0) total += distanceM(polyline[i - 1], polyline[i]);
    out.push(total);
  }
  return out;
}

/**
 * Project a point onto a polyline using a per-edge local equirectangular
 * projection. Returns { distanceAlongM, offsetM }.
 */
export function project(point, polyline, cumulative = cumulativeDistances(polyline)) {
  if (polyline.length < 2) throw new Error("polyline needs at least 2 points");
  let best = { distanceAlongM: 0, offsetM: Number.POSITIVE_INFINITY };
  for (let i = 0; i < polyline.length - 1; i++) {
    const a = polyline[i];
    const b = polyline[i + 1];
    const meanLat = rad((a.lat + b.lat) / 2);
    const mPerDegLat = (Math.PI / 180) * EARTH_RADIUS_M;
    const mPerDegLon = mPerDegLat * Math.cos(meanLat);

    const bx = (b.lon - a.lon) * mPerDegLon;
    const by = (b.lat - a.lat) * mPerDegLat;
    const px = (point.lon - a.lon) * mPerDegLon;
    const py = (point.lat - a.lat) * mPerDegLat;

    const lenSq = bx * bx + by * by;
    const t = lenSq === 0 ? 0 : Math.max(0, Math.min(1, (px * bx + py * by) / lenSq));
    const cx = t * bx;
    const cy = t * by;
    const offset = Math.hypot(px - cx, py - cy);
    if (offset < best.offsetM) {
      const edgeLen = cumulative[i + 1] - cumulative[i];
      best = { distanceAlongM: cumulative[i] + t * edgeLen, offsetM: offset };
    }
  }
  return best;
}

/** Coordinate at `d` meters along the polyline (inverse of projection). */
export function positionAtDistance(polyline, cumulative, d) {
  if (d <= 0) return { ...polyline[0] };
  const total = cumulative[cumulative.length - 1];
  if (d >= total) return { ...polyline[polyline.length - 1] };
  let i = 0;
  while (cumulative[i + 1] < d) i++;
  const f = (d - cumulative[i]) / (cumulative[i + 1] - cumulative[i]);
  const a = polyline[i];
  const b = polyline[i + 1];
  return { lat: a.lat + f * (b.lat - a.lat), lon: a.lon + f * (b.lon - a.lon) };
}

/**
 * Linear interpolation of distance-along-course at elapsed time t, clamped to
 * the first/last points. Twin of GhostEngine.interpolatedDistance.
 */
export function interpolatedDistance(t, points) {
  if (points.length === 0) return 0;
  const first = points[0];
  if (t <= first.t) return first.d;
  const last = points[points.length - 1];
  if (t >= last.t) return last.d;
  let lo = 0;
  let hi = points.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (points[mid].t <= t) lo = mid;
    else hi = mid;
  }
  const a = points[lo];
  const b = points[hi];
  if (b.t <= a.t) return a.d;
  return a.d + ((t - a.t) / (b.t - a.t)) * (b.d - a.d);
}
