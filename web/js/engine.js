/**
 * The race engine, ported from GhostRaceKit (GhostEngine.swift,
 * GateDetector.swift, RaceCueScheduler.swift). Pure logic, no DOM. A live
 * opponent is just a ghost whose points arrive over the wire instead of from
 * storage — the same engine powers both modes.
 */
import { distanceM, interpolatedDistance } from "./geo.js";

/** The core race comparator: where I stand vs. the opponent, and what just happened. */
export class GhostEngine {
  constructor(
    courseDistanceM,
    opponentPoints = [],
    { opponentDurationS = null, leadHysteresisM = 3, finalStretchM = 100 } = {},
  ) {
    this.courseDistanceM = courseDistanceM;
    this.opponentPoints = [...opponentPoints].sort((a, b) => a.t - b.t);
    this.opponentDurationS = opponentDurationS;
    this.leadHysteresisM = leadHysteresisM;
    this.finalStretchM = finalStretchM;
    this.leader = "tied";
    this.announcedFinalStretch = false;
    this.finished = false;
    this.recentTicks = [];
  }

  /** Live mode: a fresh opponent position arrived over the wire. */
  updateOpponent(point) {
    const last = this.opponentPoints[this.opponentPoints.length - 1];
    if (last && point.t <= last.t) return; // drop stale / out-of-order
    this.opponentPoints.push(point);
  }

  tick(elapsedS, myDistanceM) {
    const opponentD = interpolatedDistance(elapsedS, this.opponentPoints);
    const gapM = myDistanceM - opponentD;

    this.recentTicks.push({ t: elapsedS, d: myDistanceM });
    if (this.recentTicks.length > 6) this.recentTicks.shift();
    let mySpeedMps = null;
    const first = this.recentTicks[0];
    const last = this.recentTicks[this.recentTicks.length - 1];
    if (first && last && last.t - first.t >= 2) {
      mySpeedMps = (last.d - first.d) / (last.t - first.t);
    }
    let gapS = null;
    if (mySpeedMps != null && mySpeedMps > 0.5) gapS = gapM / mySpeedMps;

    const remainingM = Math.max(0, this.courseDistanceM - myDistanceM);
    const snapshot = {
      elapsedS,
      myDistanceM,
      opponentDistanceM: opponentD,
      gapM,
      gapS,
      mySpeedMps,
      courseDistanceM: this.courseDistanceM,
      remainingM,
      iAmAhead: gapM >= 0,
    };

    const events = [];
    if (this.finished) return { snapshot, events };

    // Lead changes, with hysteresis against jitter.
    if (this.leader === "tied") {
      if (gapM > this.leadHysteresisM) {
        this.leader = "me";
        events.push({ type: "tookLead" });
      } else if (gapM < -this.leadHysteresisM) {
        this.leader = "opponent";
        events.push({ type: "lostLead" });
      }
    } else if (this.leader === "me") {
      if (gapM < -this.leadHysteresisM) {
        this.leader = "opponent";
        events.push({ type: "lostLead" });
      }
    } else if (this.leader === "opponent") {
      if (gapM > this.leadHysteresisM) {
        this.leader = "me";
        events.push({ type: "tookLead" });
      }
    }

    if (!this.announcedFinalStretch && remainingM > 0 && remainingM <= this.finalStretchM) {
      this.announcedFinalStretch = true;
      events.push({ type: "finalStretch" });
    }

    if (myDistanceM >= this.courseDistanceM) {
      this.finished = true;
      const won =
        this.opponentDurationS != null
          ? elapsedS < this.opponentDurationS
          : opponentD < this.courseDistanceM;
      events.push({ type: "finished", won, myTimeS: elapsedS });
    }

    return { snapshot, events };
  }
}

/** Detects crossing a start/finish gate from noisy GPS, with hysteresis + min-travel guards. */
export class GateDetector {
  constructor(gate, { radiusM = 25, hysteresisM = 10, minTravelM = 0, startsInsideGate = false } = {}) {
    this.gate = gate;
    this.radiusM = radiusM;
    this.hysteresisM = hysteresisM;
    this.minTravelM = minTravelM;
    this.state = startsInsideGate ? "inside" : "armed";
    this.travelledM = 0;
    this.lastPosition = null;
  }

  /** Feed the next GPS fix. Returns true exactly once per genuine crossing. */
  update(position) {
    if (this.lastPosition) this.travelledM += distanceM(this.lastPosition, position);
    this.lastPosition = position;

    const d = distanceM(position, this.gate);
    if (this.state === "armed") {
      if (d > this.radiusM) return false;
      if (this.travelledM < this.minTravelM) return false;
      this.state = "inside";
      return true;
    }
    if (d > this.radiusM + this.hysteresisM) {
      this.state = "armed";
      this.travelledM = 0;
    }
    return false;
  }
}

/**
 * Turns snapshots and events into a paced stream of cues. Lead changes and the
 * finish cue immediately; routine gap updates are rate-limited; the cadence
 * tightens in the final stretch. Cue kinds: {kind:"say",text}, {kind:"play",tone},
 * {kind:"haptic",pattern}.
 */
export class RaceCueScheduler {
  constructor(opponentName, { announceIntervalS = 30, finalStretchIntervalS = 15, minQuietS = 8 } = {}) {
    this.opponentName = opponentName;
    this.announceIntervalS = announceIntervalS;
    this.finalStretchIntervalS = finalStretchIntervalS;
    this.minQuietS = minQuietS;
    this.lastCueAtS = -Infinity;
    this.lastGapAnnounceAtS = -Infinity;
    this.inFinalStretch = false;
    this.raceOver = false;
  }

  cues(snapshot, events) {
    if (this.raceOver) return [];
    const out = [];
    const name = this.opponentName;

    for (const event of events) {
      switch (event.type) {
        case "tookLead":
          out.push({ kind: "play", tone: "leadJingle" });
          out.push({ kind: "haptic", pattern: "overtake" });
          out.push({ kind: "say", text: `You took the lead from ${name}!` });
          break;
        case "lostLead":
          out.push({ kind: "play", tone: "behindWarning" });
          out.push({ kind: "haptic", pattern: "overtaken" });
          out.push({ kind: "say", text: `${name} just passed you!` });
          break;
        case "finalStretch":
          this.inFinalStretch = true;
          out.push({ kind: "play", tone: "finalStretch" });
          out.push({ kind: "say", text: `Final stretch! ${roundedMeters(snapshot.remainingM)} meters to go.` });
          break;
        case "finished": {
          this.raceOver = true;
          const time = formatDuration(event.myTimeS);
          out.push({ kind: "play", tone: event.won ? "winFanfare" : "loseTrombone" });
          out.push({
            kind: "say",
            text: event.won
              ? `Finished in ${time}. You beat ${name}!`
              : `Finished in ${time}. ${name} takes this one.`,
          });
          break;
        }
      }
    }

    if (out.length) {
      this.lastCueAtS = snapshot.elapsedS;
      this.lastGapAnnounceAtS = snapshot.elapsedS;
      return out;
    }

    const interval = this.inFinalStretch ? this.finalStretchIntervalS : this.announceIntervalS;
    if (
      snapshot.elapsedS - this.lastGapAnnounceAtS < interval ||
      snapshot.elapsedS - this.lastCueAtS < this.minQuietS
    ) {
      return [];
    }
    this.lastCueAtS = snapshot.elapsedS;
    this.lastGapAnnounceAtS = snapshot.elapsedS;
    return [{ kind: "say", text: gapPhrase(snapshot, name) }];
  }
}

export function gapPhrase(snapshot, name) {
  const ahead = snapshot.iAmAhead;
  if (snapshot.gapS != null && Math.abs(snapshot.gapS) >= 2) {
    const seconds = Math.round(Math.abs(snapshot.gapS));
    return ahead
      ? `You're ${seconds} seconds ahead of ${name}.`
      : `You're ${seconds} seconds behind ${name}.`;
  }
  const meters = roundedMeters(Math.abs(snapshot.gapM));
  if (meters === 0) return `Neck and neck with ${name}!`;
  return ahead
    ? `You're ${meters} meters ahead of ${name}.`
    : `You're ${meters} meters behind ${name}.`;
}

/** Nearest 5 under 100 m, nearest 10 beyond — what a human wants read aloud. */
export function roundedMeters(meters) {
  const m = Math.abs(meters);
  const step = m < 100 ? 5 : 10;
  return Math.round(m / step) * step;
}

export function formatDuration(seconds) {
  const total = Math.round(seconds);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}
