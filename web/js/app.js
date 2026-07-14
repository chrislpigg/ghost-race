import { api, deviceToken } from "./api.js";
import {
  GhostEngine,
  GateDetector,
  RaceCueScheduler,
  formatDuration,
} from "./engine.js";
import { project, cumulativeDistances } from "./geo.js";
import { AudioCueEngine } from "./audio.js";
import { LiveRaceClient } from "./live.js";
import { GpxPlaybackSource, GeolocationSource, loadFixture, parseGpx } from "./gpx.js";

// ---------------------------------------------------------------------------
// State + tiny helpers
// ---------------------------------------------------------------------------

const state = {
  name: localStorage.getItem("ghostrace.name") || "",
  segments: [],
  rivals: [],
  loaded: false,
};

const appEl = document.getElementById("app");

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

/** Set the screen HTML and return the container for event wiring. */
function render(html) {
  appEl.innerHTML = html;
  return appEl;
}

function toast(message) {
  const el = document.createElement("div");
  el.className = "toast";
  el.textContent = message;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 3200);
}

const GHOST_SVG = (stroke = "#A8E1EF", w = 96) => {
  const h = Math.round((w * 19) / 16);
  return `<svg width="${w}" height="${h}" viewBox="0 0 24 28" aria-hidden="true">
    <path d="M12 1C7 1 3 5 3 10v16l2.7-2 2.6 2 2.7-2 2.6 2 2.7-2 2.7 2V10c0-5-4-9-9-9z" fill="none" stroke="${stroke}" stroke-width="1.4" stroke-linejoin="round"/>
    <circle cx="8.6" cy="11" r="1.4" fill="${stroke}"/><circle cx="15.4" cy="11" r="1.4" fill="${stroke}"/>
  </svg>`;
};

/** Normalize a polyline to an SVG polyline (equirectangular, north up). */
function routeSvg(polyline, { width = 130, height = 48, showGates = false, pad = 6 } = {}) {
  if (!polyline || polyline.length < 2) return `<svg width="${width}" height="${height}"></svg>`;
  const meanLat = (polyline.reduce((s, p) => s + p.lat, 0) / polyline.length) * (Math.PI / 180);
  const xs = polyline.map((p) => p.lon * Math.cos(meanLat));
  const ys = polyline.map((p) => p.lat);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minY = Math.min(...ys), maxY = Math.max(...ys);
  const spanX = Math.max(maxX - minX, 1e-9), spanY = Math.max(maxY - minY, 1e-9);
  const w = width - pad * 2, h = height - pad * 2;
  const scale = Math.min(w / spanX, h / spanY);
  const offX = pad + (w - spanX * scale) / 2;
  const offY = pad + (h - spanY * scale) / 2;
  const pts = xs.map((x, i) => `${(offX + (x - minX) * scale).toFixed(1)},${(offY + (maxY - ys[i]) * scale).toFixed(1)}`);
  const [sx, sy] = pts[0].split(",");
  const [fx, fy] = pts[pts.length - 1].split(",");
  const gates = showGates
    ? `<circle cx="${sx}" cy="${sy}" r="3.5" fill="#EDF1F7"/><rect x="${fx - 4}" y="${fy - 4}" width="8" height="8" fill="none" stroke="#EDF1F7" stroke-width="1.5"/>`
    : "";
  return `<svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><polyline class="route-stroke" points="${pts.join(" ")}"/>${gates}</svg>`;
}

const activityGlyph = (t) => (t === "run" ? "RUN" : "RIDE");

async function refresh() {
  try {
    const [segments, rivals] = await Promise.all([api.listSegments(), api.listRivals()]);
    state.segments = segments || [];
    state.rivals = rivals || [];
    state.loaded = true;
  } catch (err) {
    toast(`Can't reach the server: ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

async function boot() {
  // Shareable deep links: ?challenge=<token> or ?race=<id>.
  const params = new URLSearchParams(location.search);
  const challenge = params.get("challenge");
  const race = params.get("race");

  if (!state.name) {
    renderOnboarding(challenge || race ? location.search : "");
    return;
  }
  await api.registerUser(state.name).catch(() => {});

  if (challenge) return renderChallenge(challenge);
  if (race) return renderJoinLive(race);
  route();
}

window.addEventListener("hashchange", route);

async function route() {
  const hash = location.hash.replace(/^#\/?/, "");
  const [screen, arg] = hash.split("/");
  if (screen === "record") return renderRecord();
  if (screen === "segment" && arg) return renderSegment(arg);
  await refresh();
  renderHome();
}

// ---------------------------------------------------------------------------
// Screens
// ---------------------------------------------------------------------------

function renderOnboarding(preservedQuery) {
  render(`
    <div class="onboard">
      ${GHOST_SVG("#A8E1EF", 100)}
      <h1 class="display" style="font-size:2.6rem">Ghost<span style="color:var(--ice)">Race</span></h1>
      <p class="tagline">Race your friends in the real world. Ghosts, live duels, and bragging rights.</p>
      <input id="name" class="field" style="max-width:300px;text-align:center" placeholder="Your name" autocomplete="off" />
      <button id="go" class="btn blaze" style="max-width:300px">Let's race</button>
      <div class="checker" style="width:140px"></div>
    </div>
  `);
  const input = document.getElementById("name");
  const go = document.getElementById("go");
  input.focus();
  const submit = async () => {
    const name = input.value.trim();
    if (!name) return;
    state.name = name;
    localStorage.setItem("ghostrace.name", name);
    try { await api.registerUser(name); } catch { /* offline is fine */ }
    // Preserve an incoming challenge/race link through onboarding.
    if (preservedQuery) { location.search = preservedQuery; return; }
    location.hash = "#/";
    boot();
  };
  go.addEventListener("click", submit);
  input.addEventListener("keydown", (e) => { if (e.key === "Enter") submit(); });
}

function renderHome() {
  const rivalsHtml = state.rivals
    .map((r) => {
      const leading = r.wins >= r.losses;
      const series = r.wins > r.losses ? "You lead the series" : r.wins < r.losses ? `${esc(r.rivalName)} leads the series` : "Series tied";
      return `<div class="card rival ${leading ? "" : "losing"}">
        <div class="who"><b>${esc(r.rivalName)}</b><span>${series}</span></div>
        <div class="score ${leading ? "win" : "loss"}">${r.wins}–${r.losses}</div>
      </div>`;
    })
    .join("");

  const segsHtml = state.segments.length
    ? state.segments
        .map(
          (s) => `<button class="card deep seg" data-seg="${s.id}">
            <span class="thumb">${routeSvg(s.polyline, { width: 54, height: 40 })}</span>
            <span class="meta"><b>${esc(s.name)}</b><span class="label">${activityGlyph(s.activityType)} · ${Math.round(s.distanceM)} M</span></span>
            <span class="chev">›</span>
          </button>`,
        )
        .join("")
    : `<div class="card" style="display:flex;flex-direction:column;gap:12px;align-items:flex-start">
        ${GHOST_SVG("#6C93A1", 48)}
        <p class="muted" style="margin:0">Record a run or ride to create your first segment — then challenge a friend to beat it.</p>
        <button class="btn blaze" data-record>Record a segment</button>
      </div>`;

  render(`
    <div class="topbar">
      <div class="brand"><span class="wordmark">Ghost<span class="ice">Race</span></span></div>
      <button class="rec-dot" data-record aria-label="Record"></button>
    </div>
    <div class="screen">
      ${state.rivals.length ? `<div class="eyebrow section-label">Rivalries</div><div class="stack">${rivalsHtml}</div>` : ""}
      <div class="eyebrow section-label">My segments</div>
      <div class="stack">${segsHtml}</div>
    </div>
  `);

  appEl.querySelectorAll("[data-record]").forEach((b) => b.addEventListener("click", () => (location.hash = "#/record")));
  appEl.querySelectorAll("[data-seg]").forEach((b) => b.addEventListener("click", () => (location.hash = `#/segment/${b.dataset.seg}`)));
}

function renderRecord() {
  render(`
    <div class="topbar">
      <button class="iconbtn" data-back>←</button>
      <span class="label" style="letter-spacing:0.3em">Record</span>
      <span style="width:28px"></span>
    </div>
    <div class="rec-screen screen">
      <div class="seg-toggle" style="width:100%;max-width:320px">
        <button data-act="run" class="on">🏃 Run</button>
        <button data-act="ride">🚴 Ride</button>
      </div>
      <div style="width:100%;max-width:320px">
        <div class="label" style="margin-bottom:6px">Position source</div>
        <select id="source" class="field">
          <option value="fixture">Demo fixture — ghost-run.gpx</option>
          <option value="gps">Live GPS (this device)</option>
          <option value="file">Upload a GPX file…</option>
        </select>
        <input id="gpxfile" type="file" accept=".gpx" style="display:none" />
        <div id="speedwrap" style="margin-top:8px">
          <span class="label">Playback speed</span>
          <select id="speed" class="field" style="margin-top:4px">
            <option value="20">20× (fast demo)</option>
            <option value="8">8×</option>
            <option value="1">1× (real time)</option>
          </select>
        </div>
      </div>
      <div style="flex:1"></div>
      <div style="text-align:center">
        <div class="rec-clock" id="clock">0:00</div>
        <div class="rec-dist" id="dist">0 m</div>
        <div id="gps" class="gps" style="margin-top:12px">Ready</div>
      </div>
      <div style="flex:1"></div>
      <button id="startstop" class="btn blaze" style="max-width:320px">Start</button>
    </div>
  `);

  let activity = "run";
  appEl.querySelectorAll("[data-act]").forEach((b) =>
    b.addEventListener("click", () => {
      activity = b.dataset.act;
      appEl.querySelectorAll("[data-act]").forEach((x) => x.classList.toggle("on", x === b));
    }),
  );
  appEl.querySelector("[data-back]").addEventListener("click", () => (location.hash = "#/"));

  const sourceSel = document.getElementById("source");
  const fileInput = document.getElementById("gpxfile");
  const speedWrap = document.getElementById("speedwrap");
  let uploadedPoints = null;
  const syncSourceUI = () => {
    speedWrap.style.display = sourceSel.value === "gps" ? "none" : "block";
    if (sourceSel.value === "file") fileInput.click();
  };
  sourceSel.addEventListener("change", syncSourceUI);
  fileInput.addEventListener("change", async () => {
    const file = fileInput.files?.[0];
    if (file) uploadedPoints = parseGpx(await file.text());
  });

  const rec = new RecordController({
    onTick: (t, dist, gps) => {
      document.getElementById("clock").textContent = formatDuration(t);
      document.getElementById("dist").textContent = `${Math.round(dist)} m`;
      const gpsEl = document.getElementById("gps");
      if (gps) {
        const good = gps.accuracy != null && gps.accuracy <= 10;
        gpsEl.className = `gps ${gps.accuracy == null ? "" : good ? "good" : "poor"}`;
        gpsEl.innerHTML = gps.accuracy != null ? `<span class="pip"></span> GPS ±${Math.round(gps.accuracy)} m` : "Recording";
      }
    },
  });

  const button = document.getElementById("startstop");
  let recording = false;
  button.addEventListener("click", async () => {
    if (!recording) {
      let source;
      const val = sourceSel.value;
      const speed = Number(document.getElementById("speed").value);
      try {
        if (val === "gps") source = new GeolocationSource();
        else if (val === "file") {
          if (!uploadedPoints) { toast("Pick a GPX file first."); return; }
          source = new GpxPlaybackSource(uploadedPoints, { speed });
        } else source = new GpxPlaybackSource(await loadFixture("ghost-run.gpx"), { speed });
      } catch (err) { toast(err.message); return; }
      recording = true;
      button.textContent = "Finish";
      button.className = "btn stop";
      sourceSel.disabled = true;
      rec.start(activity, source);
    } else {
      recording = false;
      const result = rec.stop();
      await saveSegment(result, activity);
    }
  });
}

async function saveSegment({ points, startedAtMs }, activity) {
  const polyline = points.map((p) => ({ lat: p.lat, lon: p.lon }));
  if (polyline.length < 2) { toast("Not enough movement recorded."); return; }
  const cumulative = cumulativeDistances(polyline);
  const distanceM = cumulative[cumulative.length - 1];
  if (distanceM <= 50) { toast("Need at least 50 m of movement to make a segment."); return; }
  const name = prompt("Name this segment so your rivals know what they're up against.") || `${activity === "run" ? "Run" : "Ride"} ${new Date().toLocaleString()}`;
  try {
    const segment = await api.createSegment(name, activity, polyline, distanceM);
    const effortPoints = points.map((p, i) => ({ t: p.t, d: Math.min(cumulative[i], distanceM) }));
    const durationS = effortPoints[effortPoints.length - 1].t;
    await api.createEffort(segment.id, startedAtMs, durationS, effortPoints);
    location.hash = `#/segment/${segment.id}`;
  } catch (err) {
    toast(`Couldn't save: ${err.message}`);
  }
}

async function renderSegment(segmentId) {
  render(`<div class="topbar"><button class="iconbtn" data-back>←</button><span class="label">Segment</span><span style="width:28px"></span></div><div class="screen"><div class="spinner" style="margin:40px auto"></div></div>`);
  appEl.querySelector("[data-back]").addEventListener("click", () => (location.hash = "#/"));

  let segment = state.segments.find((s) => s.id === segmentId);
  if (!segment) { await refresh(); segment = state.segments.find((s) => s.id === segmentId); }
  if (!segment) { render(`<div class="screen"><p class="muted">Segment not found.</p></div>`); return; }
  const efforts = await api.listMyEfforts(segment.id).catch(() => []);
  const best = efforts[0];

  render(`
    <div class="topbar"><button class="iconbtn" data-back>←</button><span class="label" style="letter-spacing:0.24em">${esc(segment.name)}</span><span style="width:28px"></span></div>
    <div class="seg-hero">${routeSvg(segment.polyline, { width: 480, height: 180, showGates: true })}</div>
    <div class="screen">
      <div class="stat-row">
        <div class="stat"><div class="k">Distance</div><div class="v">${Math.round(segment.distanceM)} m</div></div>
        <div class="stat" style="text-align:center"><div class="k">Type</div><div class="v">${segment.activityType === "run" ? "Run" : "Ride"}</div></div>
        <div class="stat ice" style="text-align:right"><div class="k">Your best</div><div class="v">${best ? formatDuration(best.durationS) : "—"}</div></div>
      </div>
      <div class="stack" style="margin-top:8px">
        ${best ? `<button class="btn blaze" data-challenge>Challenge a friend</button>` : ""}
        ${best ? `<button class="btn ice" data-ghost>Race your ghost</button>` : `<p class="muted">Record an effort on this segment to unlock ghost racing and challenges.</p>`}
        <button class="btn ghostline" data-live>⚡ Start a live duel</button>
      </div>
    </div>
  `);
  appEl.querySelector("[data-back]").addEventListener("click", () => (location.hash = "#/"));
  appEl.querySelector("[data-challenge]")?.addEventListener("click", async () => {
    try {
      const challenge = await api.createChallenge(best.id);
      const url = `${location.origin}/?challenge=${challenge.token}`;
      await shareOrCopy(url, `I set a time on ${segment.name}. Beat it if you can. 🏁`);
    } catch (err) { toast(err.message); }
  });
  appEl.querySelector("[data-ghost]")?.addEventListener("click", () => startGhostRaceFromEffort(segment, best, "your ghost", null));
  appEl.querySelector("[data-live]")?.addEventListener("click", async () => {
    try {
      const room = await api.createRace(segment.id);
      startLiveRace(segment, room.raceId, "your rival", true);
    } catch (err) { toast(err.message); }
  });
}

async function renderChallenge(token) {
  render(`<div class="chal"><div class="spinner"></div><p class="muted">Loading challenge…</p></div>`);
  let details;
  try {
    details = await api.challengeDetails(token);
  } catch {
    render(`<div class="chal"><div style="font-size:2rem">⚠️</div><p class="muted">Couldn't load this challenge. It may have expired, or the server is unreachable.</p><a class="btn ghostline" href="#/" onclick="location.search=''">Home</a></div>`);
    return;
  }
  const seg = details.segment;
  render(`
    <div class="chal">
      <h1 class="display head"><span class="blaze">${esc(details.challengerName)}</span> called you out</h1>
      <div class="card chal-card">
        ${routeSvg(seg.polyline, { width: 150, height: 52 })}
        <b>${esc(seg.name)}</b>
        <span class="label">${activityGlyph(seg.activityType)} · ${Math.round(seg.distanceM)} M</span>
        <span class="label" style="margin-top:6px">Time to beat</span>
        <span class="beat-v">${formatDuration(details.ghost.durationS)}</span>
      </div>
      <p class="muted" style="font-size:0.85rem;max-width:34ch">You'll race ${esc(details.challengerName)}'s ghost — live audio tells you exactly where they were.</p>
      <button id="accept" class="btn blaze" style="max-width:320px">Accept &amp; race</button>
      <a class="label" style="color:var(--muted)" href="#/" onclick="location.search=''">Later</a>
    </div>
  `);
  document.getElementById("accept").addEventListener("click", async () => {
    try { await api.acceptChallenge(token); } catch { /* idempotent */ }
    const source = await chooseRaceSource(details.ghost.durationS);
    history.replaceState({}, "", location.origin + location.pathname);
    const ghost = { points: details.ghost.points, durationS: details.ghost.durationS, athleteName: details.challengerName };
    new RaceController().beginGhost({ segment: seg, ghost, opponentName: details.challengerName, challengeToken: token, source });
  });
}

async function renderJoinLive(raceId) {
  await refresh();
  if (!state.segments.length) {
    render(`<div class="chal"><p class="muted">You need a recorded segment first — record one, then reopen this link.</p><button class="btn blaze" style="max-width:280px" onclick="location.search='';location.hash='#/record'">Record a segment</button></div>`);
    return;
  }
  const options = state.segments.map((s) => `<option value="${s.id}">${esc(s.name)} (${Math.round(s.distanceM)} m)</option>`).join("");
  render(`
    <div class="topbar"><span class="label" style="letter-spacing:0.24em">Join live duel</span></div>
    <div class="screen stack">
      <div class="card"><div class="label">Race ID</div><div class="share-id">${esc(raceId)}</div></div>
      <div class="label section-label">Race on which segment?</div>
      <select id="seg" class="field">${options}</select>
      <p class="muted" style="font-size:0.85rem">Pick the same segment as your rival for a fair duel; any segment works for a distance race.</p>
      <button id="join" class="btn blaze">Race</button>
    </div>
  `);
  document.getElementById("join").addEventListener("click", () => {
    const seg = state.segments.find((s) => s.id === document.getElementById("seg").value);
    history.replaceState({}, "", location.origin + location.pathname);
    startLiveRace(seg, raceId, "your rival", false);
  });
}

// ---------------------------------------------------------------------------
// Race entry points
// ---------------------------------------------------------------------------

async function chooseRaceSource(courseSeconds) {
  // For a race, offer the same source choice as recording via a lightweight prompt.
  const useGps = confirm("Race with live GPS on this device?\n\nOK = live GPS.\nCancel = play back the demo 'live-run.gpx' (great on a laptop).");
  if (useGps) return new GeolocationSource();
  const speed = Number(prompt("Playback speed multiplier (e.g. 20 for a fast demo, 1 for real time):", "20")) || 20;
  return new GpxPlaybackSource(await loadFixture("live-run.gpx"), { speed });
}

async function startGhostRaceFromEffort(segment, effort, opponentName, challengeToken) {
  const source = await chooseRaceSource(effort.durationS);
  const ghost = { points: effort.points, durationS: effort.durationS, athleteName: opponentName };
  new RaceController().beginGhost({ segment, ghost, opponentName, challengeToken, source });
}

async function startLiveRace(segment, raceId, opponentName, isHost) {
  const source = await chooseRaceSource(0);
  new RaceController().beginLive({ segment, raceId, opponentName, isHost, source });
}

async function shareOrCopy(url, text) {
  if (navigator.share) {
    try { await navigator.share({ text, url }); return; } catch { /* cancelled */ }
  }
  try { await navigator.clipboard.writeText(url); toast("Challenge link copied to clipboard."); }
  catch { prompt("Copy this challenge link:", url); }
}

// ---------------------------------------------------------------------------
// Recording
// ---------------------------------------------------------------------------

class RecordController {
  constructor({ onTick }) {
    this.onTick = onTick;
    this.points = [];
    this.source = null;
    this.startedAtMs = null;
  }
  start(activity, source) {
    this.points = [];
    this.startedAtMs = Date.now();
    this.source = source;
    source.onFix = (coord, t) => {
      this.points.push({ lat: coord.lat, lon: coord.lon, t });
      const cum = cumulativeDistances(this.points.map((p) => ({ lat: p.lat, lon: p.lon })));
      this.onTick(t, cum[cum.length - 1] || 0, { accuracy: coord.accuracy });
    };
    source.start();
  }
  stop() {
    this.source?.stop();
    return { points: this.points, startedAtMs: this.startedAtMs };
  }
}

// ---------------------------------------------------------------------------
// Race controller — the shared engine drives one full-screen overlay
// ---------------------------------------------------------------------------

class RaceController {
  constructor() {
    this.audio = new AudioCueEngine();
    this.el = null;
    this.engine = null;
    this.scheduler = null;
    this.gate = null;
    this.source = null;
    this.cumulative = null;
    this.courseDistanceM = 0;
    this.raceStartT = null;
    this.startedAtMs = null;
    this.uploadedPoints = [];
    this.live = null;
    this.myUserId = null;
    this.finishedLocally = false;
    this.segment = null;
    this.opponentName = "";
    this.challengeToken = null;
    this.lastAhead = null;
    this.myPoints = [];
    this.done = false;
    this.lastWon = false;
  }

  mount() {
    this.el = document.createElement("div");
    this.el.className = "race";
    document.body.appendChild(this.el);
    this.audio.unlock();
  }

  common(segment, opponentName) {
    this.segment = segment;
    this.opponentName = opponentName;
    this.courseDistanceM = segment.distanceM;
    this.cumulative = cumulativeDistances(segment.polyline);
    this.scheduler = new RaceCueScheduler(opponentName);
    this.mount();
  }

  beginGhost({ segment, ghost, opponentName, challengeToken, source }) {
    this.common(segment, opponentName);
    this.challengeToken = challengeToken;
    this.source = source;
    this.engine = new GhostEngine(this.courseDistanceM, ghost.points, { opponentDurationS: ghost.durationS });
    this.gate = new GateDetector(segment.polyline[0], { radiusM: segment.gateRadiusM || 25, startsInsideGate: false });
    this.renderPre("Head to the start line. The race begins the moment you cross it.");
    source.onFix = (coord, t) => this.onFixGhost(coord, t);
    source.onDone = () => {};
    source.start();
  }

  beginLive({ segment, raceId, opponentName, isHost, source }) {
    this.common(segment, opponentName);
    this.source = source;
    this.engine = new GhostEngine(this.courseDistanceM, [], {});
    this.renderPre(`Waiting for ${esc(opponentName)}…`, raceId);
    this.live = new LiveRaceClient(raceId, deviceToken());
    this.live
      .on("joined", ({ you, peers }) => { this.myUserId = you; if (peers.length === 2) this.setStatus("Both racers in. Get ready!"); this.live.ready(); })
      .on("peerJoined", () => { this.setStatus(`${esc(opponentName)} is here. Get ready!`); this.live.ready(); })
      .on("countdown", ({ startAtMs, serverNowMs }) => this.startCountdown(startAtMs, serverNowMs))
      .on("opponentPosition", ({ t, d }) => this.engine.updateOpponent({ t, d }))
      .on("opponentFinished", ({ durationS }) => this.engine.updateOpponent({ t: durationS, d: this.courseDistanceM }))
      .on("result", ({ winnerId }) => this.officialResult(winnerId))
      .on("opponentDisconnected", ({ graceMs }) => this.setStatus(`${esc(opponentName)} lost connection — ${Math.round(graceMs / 1000)}s grace.`))
      .on("opponentReconnected", () => this.setStatus(`${esc(opponentName)} is back.`))
      .on("error", ({ message }) => this.abort(message))
      .on("socketClosed", () => { if (!this.finishedLocally && !this.done) this.abort("Connection to the race server was lost."); });
    this.live.connect();
  }

  // --- ghost fix handling: gate then tick ---
  onFixGhost(coord, t) {
    if (this.raceStartT == null) {
      if (this.gate.update({ lat: coord.lat, lon: coord.lon })) {
        this.raceStartT = t;
        this.startedAtMs = Date.now();
        this.audio.perform([{ kind: "play", tone: "startBeep" }, { kind: "say", text: `Go! Racing ${this.opponentName}.` }]);
        this.renderHud();
      }
      return;
    }
    this.tick(coord, t - this.raceStartT);
  }

  startCountdown(startAtMs, serverNowMs) {
    const skew = Date.now() - serverNowMs;
    const localStartMs = startAtMs + skew;
    this.renderCountdown(localStartMs);
    const tickCheck = () => {
      const remaining = localStartMs - Date.now();
      if (remaining <= 0) {
        this.raceStartT = 0;
        this.startedAtMs = Date.now();
        this.renderHud();
        this.source.onFix = (coord, t) => this.tick(coord, t);
        this.source.start();
      } else {
        requestAnimationFrame(tickCheck);
      }
    };
    requestAnimationFrame(tickCheck);
  }

  tick(coord, elapsed) {
    if (this.finishedLocally || elapsed < 0) return;
    const p = project({ lat: coord.lat, lon: coord.lon }, this.segment.polyline, this.cumulative);
    const myD = Math.min(p.distanceAlongM, this.courseDistanceM);
    this.myPoints.push({ t: elapsed, d: myD });
    if (this.live) this.live.sendPosition(elapsed, myD);
    const { snapshot, events } = this.engine.tick(elapsed, myD);
    this.updateHud(snapshot);
    const cues = this.scheduler.cues(snapshot, events);
    if (cues.length) this.audio.perform(cues);
    for (const e of events) {
      if (e.type === "finished") { this.finishedLocally = true; this.completeRace(e.won, e.myTimeS); }
    }
  }

  async completeRace(won, myTimeS) {
    this.source?.stop();
    const time = formatDuration(myTimeS);
    let summary;
    if (this.live) {
      this.live.finish(myTimeS);
      summary = "Waiting for the official result…";
    } else if (this.challengeToken) {
      summary = won ? `You beat ${this.opponentName}!` : `${this.opponentName} takes this one.`;
      try {
        await api.completeChallenge(this.challengeToken, this.startedAtMs || Date.now(), myTimeS, this.myPoints);
      } catch {
        summary += " (Couldn't report the result — you may be offline.)";
      }
    } else {
      summary = won ? `You beat ${this.opponentName}.` : `${this.opponentName} won this time.`;
    }
    this.renderResult(won, `Finished in ${time}. ${summary}`);
  }

  officialResult(winnerId) {
    if (!this.done) return;
    const won = this.myUserId ? winnerId === this.myUserId : this.lastWon;
    this.renderResult(won, `Official: ${won ? "you win!" : `${this.opponentName} wins.`}`);
  }

  // --- rendering ---
  renderPre(status, raceId) {
    this.el.className = "race";
    this.el.innerHTML = `
      <div class="race-top"><button data-quit>✕ quit</button><span>${esc(this.segment.name)}</span></div>
      <div class="race-body">
        ${GHOST_SVG("#A8E1EF", 84)}
        <div class="spinner"></div>
        <p id="status" style="max-width:26ch">${status}</p>
        ${raceId ? `<div class="share-row"><span class="label">Race ID</span><span class="share-id">${esc(raceId)}</span><button class="btn ice" data-invite>Invite your rival</button></div>` : ""}
      </div>`;
    this.wireQuit();
    this.el.querySelector("[data-invite]")?.addEventListener("click", () => shareOrCopy(`${location.origin}/?race=${raceId}`, "Race me right now on GhostRace! 🏁"));
  }

  setStatus(text) { const s = this.el?.querySelector("#status"); if (s) s.innerHTML = text; }

  renderCountdown(localStartMs) {
    this.el.className = "race";
    const R = 88, C = 2 * Math.PI * R;
    this.el.innerHTML = `
      <div class="race-top"><button data-quit>✕ quit</button><span>Live duel</span></div>
      <div class="race-body">
        <div class="count-wrap">
          <svg class="count-ring" viewBox="0 0 190 190"><circle class="track" cx="95" cy="95" r="${R}"/><circle class="fill" id="ring" cx="95" cy="95" r="${R}" stroke-dasharray="${C}" stroke-dashoffset="0"/></svg>
          <div class="count-n" id="cn">3</div>
        </div>
        <div class="state" style="font-size:0.9rem;color:var(--muted)">Get ready</div>
        <div class="race-foot">server countdown · both phones fire GO together</div>
      </div>`;
    this.wireQuit();
    const total = Math.max(0.5, (localStartMs - Date.now()) / 1000);
    const ring = this.el.querySelector("#ring");
    const cn = this.el.querySelector("#cn");
    const draw = () => {
      const remaining = (localStartMs - Date.now()) / 1000;
      if (remaining <= 0) { cn.textContent = "GO!"; cn.classList.add("count-go"); ring.style.strokeDashoffset = C; return; }
      cn.textContent = String(Math.ceil(remaining));
      ring.style.strokeDashoffset = C * (1 - remaining / total);
      requestAnimationFrame(draw);
    };
    draw();
  }

  renderHud() {
    this.el.innerHTML = `
      <div class="race-top"><button data-quit>✕ quit</button><span>${esc(this.segment.name)}</span></div>
      <div class="race-body">
        <div id="flash"></div>
        <div class="delta" id="delta">+0<small>s</small></div>
        <div class="state" id="state">Ahead</div>
        <div class="hud-full">
          <div class="trackbar" id="trackbar">
            <div class="tb-line"></div><div class="tb-start"></div><div class="tb-finish"></div>
            <div class="racer opp" id="opp" style="left:0"><span>${GHOST_SVG("#A8E1EF", 16)}</span><span class="tag" style="color:var(--ice)">${esc(this.opponentName)}</span></div>
            <div class="racer you" id="you" style="left:0"><span class="tag" style="color:var(--blaze-hot)">You</span><span class="chev"></span></div>
          </div>
          <div class="hud-stats">
            <div><div class="k">Time</div><div class="v" id="s-time">0:00</div></div>
            <div style="text-align:center"><div class="k">Pace</div><div class="v" id="s-pace">—</div></div>
            <div style="text-align:right"><div class="k">To go</div><div class="v" id="s-togo">${Math.round(this.courseDistanceM)} m</div></div>
          </div>
        </div>
        <div class="race-foot" id="foot"></div>
      </div>`;
    this.wireQuit();
  }

  updateHud(s) {
    if (!this.el || !this.el.querySelector("#delta")) return;
    const ahead = s.iAmAhead;
    this.el.className = `race ${ahead ? "ahead" : "behind"}`;
    const deltaText = s.gapS != null ? `${s.gapS >= 0 ? "+" : "−"}${Math.abs(Math.round(s.gapS))}` : `${s.gapM >= 0 ? "+" : "−"}${Math.abs(Math.round(s.gapM))}`;
    const unit = s.gapS != null ? "s" : "m";
    this.el.querySelector("#delta").innerHTML = `${deltaText}<small>${unit}</small>`;
    this.el.querySelector("#state").textContent = ahead ? "Ahead" : "Behind";
    this.el.querySelector("#s-time").textContent = formatDuration(s.elapsedS);
    this.el.querySelector("#s-togo").textContent = `${Math.round(s.remainingM)} m`;
    this.el.querySelector("#s-pace").textContent = this.paceText(s);
    // Keep dots a few % off each end so the glyphs never clip the gates.
    const frac = (d) => (this.courseDistanceM > 0 ? Math.min(0.97, Math.max(0.03, d / this.courseDistanceM)) : 0.03);
    this.el.querySelector("#you").style.left = `${frac(s.myDistanceM) * 100}%`;
    this.el.querySelector("#opp").style.left = `${frac(s.opponentDistanceM) * 100}%`;

    if (this.lastAhead != null && this.lastAhead !== ahead) this.flash(ahead ? "You took the lead" : `${this.opponentName} took the lead`);
    this.lastAhead = ahead;
  }

  paceText(s) {
    if (s.mySpeedMps == null || s.mySpeedMps <= 0.3) return "—";
    if (this.segment.activityType === "ride") return `${(s.mySpeedMps * 3.6).toFixed(1)} km/h`;
    return `${formatDuration(1000 / s.mySpeedMps)}/km`;
  }

  flash(text) {
    const f = this.el?.querySelector("#flash");
    if (!f) return;
    f.innerHTML = `<span class="lead-flash">${esc(text)}</span>`;
    setTimeout(() => { if (f.textContent === text) f.innerHTML = ""; }, 2500);
  }

  renderResult(won, summary) {
    this.done = true;
    this.lastWon = won;
    this.el.className = `race ${won ? "victory" : "defeat"}`;
    this.el.innerHTML = `
      <div class="race-body result ${won ? "" : "lost"}">
        ${won ? `<div class="checker" style="width:130px"></div>` : GHOST_SVG("#A8E1EF", 64)}
        <h2 class="display word">${won ? "Victory" : "Defeat"}</h2>
        <p class="muted" style="max-width:26ch">${esc(summary)}</p>
        ${won ? "" : `<p style="color:var(--blaze-hot);font-style:italic">Rematch and take it back.</p>`}
        <div class="race-actions">
          <button class="btn ${won ? "blaze" : "ghostline"}" data-done>${won ? "Rub it in later" : "Done"}</button>
        </div>
      </div>`;
    this.el.querySelector("[data-done]").addEventListener("click", () => this.dismiss());
  }

  abort(reason) {
    this.done = true;
    this.el.className = "race";
    this.el.innerHTML = `<div class="race-body"><div style="font-size:2.5rem">🏳️</div><p style="max-width:26ch">${esc(reason)}</p><div class="race-actions"><button class="btn ghostline" data-done>Close</button></div></div>`;
    this.el.querySelector("[data-done]").addEventListener("click", () => this.dismiss());
  }

  wireQuit() {
    this.el.querySelector("[data-quit]")?.addEventListener("click", () => { this.source?.stop(); this.live?.close(); this.dismiss(); });
  }

  dismiss() {
    this.source?.stop();
    this.live?.close();
    this.el?.remove();
    this.el = null;
    location.hash = "#/";
    route();
  }
}

// ---------------------------------------------------------------------------

boot();
