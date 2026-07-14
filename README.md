# GhostRace 🏁

Mario Kart for the real world: record a run or ride segment, challenge a
friend, and race them — their ghost or live — with real-time audio
announcements, victory jingles, warning beeps, and haptics.

**Business case:** see [`docs/market-research.md`](docs/market-research.md).
TL;DR — every ingredient exists scattered across Strava/Garmin/Zwift and a
graveyard of tiny indies, but nobody combines *outdoor + head-to-head social
challenges + game feel*. The wedge is ghost racing (no scheduling problem);
live duels are the hook. The one metric that decides whether this is a
business: **does a challenge link convert a friend into a completed race?**

## Layout

```
ghost-race/
  docs/market-research.md     Market/business research (also published as an Artifact)
  server/                     TypeScript API + WebSocket race relay (SQLite, zero infra)
                              also serves the web client as static files (same origin)
  ios/
    project.yml               XcodeGen definition → GhostRace.xcodeproj
    GhostRaceKit/              SwiftPM package: ALL race math, pure Foundation, fully unit-tested
    GhostRace/                 SwiftUI app: GPS, audio/haptics, screens, networking
    Fixtures/                 GPX files for Xcode simulator location playback
  web/                        Browser client: same design, same server, no build step
    js/                       ES modules — geo + engine (JS twin), api, live WS, audio, gpx
    test/                     Node tests pinning the web math + racing pipeline
    fixtures/                 GPX files for in-browser playback / demo
  tools/                      Fixture generator + JS twin of the geo math (see below)
```

### Architecture in one sentence

A live rival is just a ghost whose points arrive over a WebSocket instead of
from storage — one `GhostEngine` (in `GhostRaceKit`) powers both modes, and
audio/haptics/HUD subscribe to its events.

```
GPS fix ─► project onto segment ─► GhostEngine.tick ─► events ─► RaceCueScheduler ─► speech/tones/haptics
                                        ▲                                              + Race HUD
        ghost points (stored) ──────────┤
        live points (WebSocket relay) ──┘
```

## Server — run it now (any machine with Node 22)

```bash
cd server
npm install
npm test        # 17 tests: data layer, REST, race rooms, scripted 2-client live race
npm run dev     # http://localhost:8787, SQLite file ghostrace.sqlite
```

## Web — the browser version (no build step, no Mac)

The web client is plain ES modules served by the same Node server, so there's
no bundler and no CORS. It reuses the exact race engine (a JS twin of
GhostRaceKit, pinned to the same `crosscheck.json` fixture) and speaks the same
REST + WebSocket protocol as the iOS app.

```bash
cd server
npm run dev            # serves the app + API on http://localhost:8787
# then open http://localhost:8787 in a browser
```

Ghost racing works entirely on a laptop — no GPS required:

1. Open the app, enter a name.
2. **Record → source "Demo fixture — ghost-run.gpx"** at 20× speed → Start →
   Finish → name the segment. (You've just recorded the ghost's effort.)
3. Open that segment → **Race your ghost** → when prompted, choose *Cancel* to
   play back `live-run.gpx` at 20×. Watch the HUD: the delta flips green/red, the
   TrackBar dots move, the overtake fires in the final stretch with a jingle, and
   you finish with the victory fanfare — the same scripted race as the iOS
   simulator test, in the browser.
4. **Challenge a friend** copies a `…/?challenge=<token>` link; open it in another
   browser/profile to run the full viral loop (accept → race the ghost → the
   rivalry record updates on both sides).
5. **Start a live duel** opens a room with a `…/?race=<id>` link; open it in a
   second window, pick a segment, and both race in real time against the server's
   synchronized countdown.

Live GPS (the "Live GPS" source) works on a phone browser over HTTPS or on
`localhost`. Tones use WebAudio and announcements use the Web Speech API, so keep
the tab's sound on.

Verify the web race math and pipeline headlessly (any Node 22):

```bash
node --test web/test/*.test.mjs   # geo cross-check, engine outcome, full ghost-race pipeline
```

## iOS — first build on your Mac

The Swift code was authored in a Linux environment **without a Swift
compiler**. The math is pinned by tests (see Cross-check below), but expect
possibly a few trivial compile fixups on first build — that's anticipated,
not a surprise.

```bash
brew install xcodegen
cd ios
xcodegen generate
open GhostRace.xcodeproj
```

1. **Run the unit tests first** (⌘U, or `swift test` inside `ios/GhostRaceKit`
   on macOS). They cover distance-along-segment projection, gate-crossing
   hysteresis, ghost interpolation, lead-change events, and cue rate-limiting.
2. **Simulated ghost race end-to-end:**
   - Start the server (`npm run dev`), set the simulator app's Settings →
     Server URL to `http://localhost:8787`.
   - Run the app, record a "segment" using **Features → Location → GPX file →
     `ios/Fixtures/ghost-run.gpx`** (230 s over a 937 m course), save it.
   - Race your ghost on that segment, this time playing back
     **`live-run.gpx`** (225 s, negative split). You should hear: gap
     announcements every ~30 s, the *final stretch* cue near the end, the
     **overtake jingle at ~212 s** (the fixtures are built so the pass happens
     in the last 6%), and the victory fanfare at ~225 s.
3. **Live duel with two simulators:** launch the app in two simulators, each
   with a different name, create a live duel from a segment on one, join by
   race id on the other (MVP: share the id out-of-band), both play back their
   GPX files. Verify the synchronized countdown and live position relay.
4. **The real test:** put it on your phone (free provisioning works — no paid
   developer account needed), record a real segment, send yourself the
   challenge link, and race your own ghost.

## Cross-check: how untested-on-arrival Swift stays honest

`tools/geo.mjs` is a line-for-line JS twin of `Geo.swift` +
`GhostEngine.interpolatedDistance`. `tools/build-fixtures.mjs` generates:

- the two GPX fixtures (and simulates the full race: winner, overtake time),
- `ios/GhostRaceKit/Tests/GhostRaceKitTests/Fixtures/crosscheck.json` — expected
  projection/interpolation values and the race outcome.

`CrossCheckTests.swift` replays all of it through the Swift implementation and
must agree within 0.5 m / 1 s. Validate the JS side anywhere with:

```bash
node --test tools/fixtures.test.mjs
```

If you change the geo math on either side, change both and regenerate:
`node tools/build-fixtures.mjs`.

## What's deliberately deferred (v2 notes)

- **Push notifications** (challenge links go via share sheet for now) and real
  auth (device tokens only).
- **Live race invites** — currently the race id is shared out-of-band; v2 is a
  `ghostrace://race/<id>` deep link + push.
- **Catch-up mechanics / power-ups** (Zwift-style) — the engine's event stream
  is where they'd hook in.
- **Handicapping** ("equalized" races across fitness levels) — the best idea
  from the Racefully graveyard, a natural Pro feature.
- **Watch app**, Android, TestFlight distribution.

## Known risks

- GPS noise at start/finish gates is the classic hard problem.
  `GateDetector` ships with hysteresis + minimum-travel guards; tune
  `gateRadiusM` per segment with real-world tracks.
- Background GPS + audio and battery behavior need real-device validation;
  the simulator only proves the logic.
- `NSAllowsLocalNetworking` is set for LAN development; remove before any
  distribution and put the server behind TLS.
