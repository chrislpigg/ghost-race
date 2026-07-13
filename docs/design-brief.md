# GhostRace — UI Design Brief (handoff)

This is the complete design handoff for the GhostRace iOS app. It covers product
positioning, design principles, the full screen inventory with every state and its
data, component specs, flows, and constraints. The functional app already exists in
SwiftUI (`ios/GhostRace/`); this brief is the input for a full visual design pass —
every screen may be redesigned, but states, data, and flows below are the contract.

---

## 1. Product in one paragraph

**"Mario Kart for the real world."** Record a run or ride segment, challenge a
specific friend, and race them head-to-head with game-like real-time feedback —
audio announcements when you're behind, a jingle when you take the lead, haptics on
overtakes. Two race modes, one experience: **ghost racing** (race a friend's recorded
effort, asynchronously) and **live duels** (both racers run at the same moment,
synced by a server countdown). Running and cycling, iPhone-native, iOS 17+.

The emotional core is the **rivalry**: "you lead the series 3–2." Not leaderboards
against strangers — a taunting, personal, best-friend feud.

## 2. Brand personality & voice

- **Competitive-playful.** Trash talk, not corporate fitness. Existing copy sets the
  register — keep it: "Throw down the gauntlet", "Beat it if you can. 🏁",
  "Rematch and take it back.", "Rub it in later" (the victory dismiss button),
  "…who really owns it."
- **Arcade energy, athletic credibility.** Mario Kart feel in the race HUD (dots on
  a track, countdown, jingles) but the data must read as legit sports metrics
  (pace, gap in seconds, monospaced digits).
- **Fast and taunting, never bureaucratic.** The challenge-accept screen is the
  viral loop; it should feel like being called out, not like filling in a form.
- Emoji are currently load-bearing (🏁 ⚔️ 🏆 😤 🏃 🚴, 🔵/🟠 racer dots). The design
  may replace them with proper illustration/iconography — but keep the personality
  they carry.

## 3. Design principles (ranked)

1. **Glanceable at speed.** The race HUD is read mid-stride or on a handlebar mount.
   One huge number. Color tells the story before any text is legible.
2. **State = color.** Racing ahead → green field; behind → red field. Instant,
   pre-cognitive. (Must also work for color-blind users — pair color with
   shape/direction, see §8.)
3. **Audio-first during the race.** The screen is secondary to spoken cues ("15
   meters behind Alex") and tones. The HUD confirms what the ears already know.
4. **Dark, high-contrast race mode.** The race flow forces dark scheme today;
   sunlight legibility is the constraint (outdoor use, max brightness, sweat/rain).
5. **The rivalry is the home screen.** Head-to-head records front and center;
   segments are the arenas, rivals are the point.

## 4. Design system needs

- **Color:** a brand identity plus two semantic race states:
  - *Ahead* (currently deep green `#063F1A`-ish field) and *Behind* (dark red
    `#4D0D0D`-ish field). These are full-screen background states, so pick tones
    that big type and white UI sit on comfortably.
  - Win/loss accents on rival records (currently system green/red).
  - GPS quality: good (≤10 m accuracy, green) vs. poor (orange).
- **Typography:** numbers are the hero. Current HUD: 88 pt black rounded
  monospaced-digit delta; 140 pt countdown; 72 pt record timer. Labels are small
  bold caps with wide tracking ("AHEAD", "GET READY", "TIME / PACE / TO GO").
  Design should define a numeric display scale + a text scale.
- **Iconography:** record dot, settings gear, share, bolt (live duel), person.2
  (challenge), figure.run (ghost race), location/GPS states, flag.slash (aborted).
  SF Symbols today; custom set welcome.
- **Motion:** racer dots ease along the track bar (0.8 s); countdown uses numeric
  content transitions. Lead changes deserve a signature moment (flash, dot overtake
  animation) — sound and haptics already fire there.
- **Sound & haptics are part of the brand** (not designable in Figma, but name
  them): behind = warning beeps, taking the lead = jingle, distinct
  overtaking/overtaken haptic patterns, winner taunt on results. Visual design
  should have matching moments.

## 5. Screen inventory (every state is a contract)

### 5.1 Onboarding (full-screen overlay, first launch)
- Content: app mark (🏁), name, tagline ("Race your friends in the real world.
  Ghosts, live duels, and bragging rights."), single name field, primary CTA
  ("Let's race", disabled until a name is entered).
- One step only. No account, no email — device-token auth is invisible.

### 5.2 Home
- **Sections:** optional connection-error banner (orange, wifi icon) → "Rivals"
  list → "My segments" list.
- **Rival row:** rival name, series line ("You lead the series" / "Alex leads the
  series" / "Series tied"), big monospaced record "3–2" colored by who leads.
- **Segment row:** name, activity glyph (run/ride), distance in meters. Tap →
  Segment detail.
- **Empty state (no segments):** "Record a run or ride to create your first
  segment — then challenge a friend to beat it." The record CTA is the way in.
  (Rivals section hides entirely when empty — first-run Home is basically the
  empty state + Record button. Design this moment; it's the first impression.)
- **Toolbar:** Record (primary), Settings.
- Pull-to-refresh.

### 5.3 Settings (sheet)
- Profile name field; server URL field (dev/testing affordance — keep it plain,
  it's not consumer-facing polish territory). Done commits + re-registers.

### 5.4 Record (full-screen cover)
- **Pre-start:** segmented Run 🏃 / Ride 🚴 picker; big zeroed timer; GPS status
  chip — "Acquiring GPS…" (gray) → "GPS ±8m" (green when ≤10 m, orange when
  worse); green Start button (full-width).
- **Recording:** live timer (72 pt monospaced), distance in meters, GPS chip; red
  Finish button. Swipe-to-dismiss disabled; Cancel in toolbar.
- **Save:** name-the-segment prompt ("Name this segment so your rivals know what
  they're up against."), Save / Discard(destructive). Currently a system alert —
  a designed save sheet is an upgrade opportunity.
- **Error state:** "Not enough movement recorded to make a raceable segment (need
  at least 50 m)."

### 5.5 Segment detail
- **Facts:** distance, activity type, "Your best" time (when an effort exists).
- **Actions:** Race your ghost · Challenge a friend (both only when a best effort
  exists) · Start a live duel (always; shows "Creating race…" progress state).
- Upgrade opportunity: today this is a plain list. A designed version could show
  the segment as a hero (map/route silhouette from the stored polyline, best-time
  stat block, effort history later).

### 5.6 Share challenge (sheet, medium detent)
- "Throw down the gauntlet" headline; explainer ("Send this link. When they open
  it in GhostRace, they race your ghost on {segment} — and you'll both see who
  really owns it."); one big ShareLink CTA. Prefilled message: "I just set a time
  on {segment}. Beat it if you can. 🏁".

### 5.7 Challenge accept (sheet — opened from `ghostrace://challenge/<token>`)
- **The viral-loop screen. Highest design priority after the race HUD.**
- **Loaded:** ⚔️ mark; "{Challenger} challenged you!"; card with segment name,
  activity + distance, and **"Time to beat: 12:34"** (the hook); explainer line;
  full-width "Accept & race" CTA; "Later" escape.
- **Loading:** spinner "Loading challenge…".
- **Error:** "Couldn't load this challenge. It may have expired, or the server is
  unreachable."

### 5.8 Join live duel (sheet — from `ghostrace://race/<id>`)
- Race ID (monospaced); picker of my segments to race on; footer explains same
  segment = fair duel, any segment = distance duel; Race CTA (disabled with no
  selection); empty state if the user has no segments yet.

### 5.9 Race flow (full-screen cover, forced dark)
One container, five phases:

1. **Pre-race / heading to start** (ghost mode): spinner + "Head to the start
   line. The race begins the moment you cross it."
2. **Waiting for opponent** (live mode, host): status line, Race ID card with
   monospaced ID and **"Invite your rival"** share button (message: "Race me right
   now on GhostRace! 🏁").
3. **Countdown:** server-synced. 140 pt number counting 3-2-1 with "GET READY"
   caps, then green "GO!". This is a signature moment — design it like a game.
4. **Racing HUD** (the flagship screen):
   - Full-bleed state color (ahead-green / behind-red).
   - **Delta headline:** "+7s" or "−12s" (falls back to meters "+45m" before pace
     data exists) at 88 pt black rounded monospaced; "AHEAD"/"BEHIND" caps below.
   - **TrackBar** — the Mario Kart strip: a horizontal course line, finish flag at
     the end, two labeled racer dots (You above / opponent below) easing along by
     distance-covered fraction. Both dots pin inside the bar's ends.
   - **Stat row:** TIME (elapsed) · PACE (min/km for runs, km/h for rides, "—"
     when nearly stopped) · TO GO (meters remaining).
   - Optional footnote status line (connection notices, e.g. opponent disconnect
     grace: opponent keeps moving on last-known interpolation).
   - Quit in toolbar.
5. **Result:** Victory (🏆 "Victory!", dismiss CTA "Rub it in later") / Defeat
   (😤 "Defeat", "Rematch and take it back.", CTA "Done"); one-line summary of the
   final gap. Rematch as a real button is a v1.5 design hook.
6. **Aborted:** flag.slash icon + reason text + Close (e.g. opponent never joined,
   room timeout).

## 6. Flows

**The viral loop (design for this first):**
1. A records a segment → names it → Segment detail
2. A taps "Challenge a friend" → share sheet → link lands in iMessage with taunt copy
3. B opens link → Challenge accept ("A challenged you! Time to beat: 12:34") →
   Accept & race → heads to the segment start → gate-crossing auto-starts the race
   → races A's ghost with audio/haptics → Result
4. Result posts → both users' rival records update → B counter-challenges. Loop.

**Live duel:** A opens segment → "Start a live duel" → waiting room with share
link → B opens `ghostrace://race/<id>` → picks a segment → both ready → synced
countdown → both race simultaneously with the same HUD → result + rivalry update.

**Solo loop:** record → race your own ghost (self-improvement mode, same HUD).

## 7. Information architecture notes

- No tab bar today: Home is the single root; everything else is sheets and
  full-screen covers. Designer may propose a tab structure (e.g. Rivals / Record /
  Segments) if the content justifies it — but v1 content is thin, so a single
  strong Home may still be right.
- Deep links: `ghostrace://challenge/<token>` and `ghostrace://race/<id>` open
  their sheets over whatever is on screen.

## 8. Constraints & accessibility

- **Platform:** SwiftUI, iOS 17+, iPhone only (portrait primary; race HUD should
  tolerate landscape for handlebar mounts — currently untested).
- **Outdoor legibility:** direct sun, max brightness, gloves/sweat. Contrast over
  subtlety in the race flow.
- **Color-blindness:** ahead/behind must not rely on green vs. red alone — pair
  with the sign on the delta (+/−), the AHEAD/BEHIND wordmark, and dot positions.
  Consider distinct shapes for the two racer dots (currently 🔵 vs 🟠).
- **Dynamic Type:** list screens should scale; the race HUD may cap scaling but
  the delta is already enormous.
- **VoiceOver:** secondary during a race (the app literally talks), but every
  pre/post-race screen must be fully labeled.
- **One-hand + interrupted use:** big tap targets on anything used mid-activity
  (Finish, Quit). No precision gestures during a race.
- **Audio ducking:** cues play over the user's own music — visual design should
  assume music is playing and headphones are in.

## 9. Explicitly out of scope for this pass (v2 hooks — leave room)

- Power-ups / catch-up boosts (Mario Kart items) — the HUD layout should have
  space to grow these.
- Push notifications for challenge invites (today: share links only).
- Route map rendering (polylines exist in the data; a map on segment detail is a
  natural v1.5).
- Effort history / progress charts per segment.
- Android, Watch, widgets, Live Activities (a Dynamic Island race delta is an
  obvious future win — worth keeping in mind when designing the delta treatment).

## 10. Open design questions (designer's call, flag your choice)

1. Brand mark and name treatment — the 🏁 placeholder needs a real identity.
   "Ghost" imagery is available and on-theme for the async mode.
2. Racer identity on the TrackBar: colors, avatars, or ghost-vs-runner glyphs?
3. Does the segment detail become a visual hero (route silhouette) in v1, or stay
   utilitarian?
4. Countdown and lead-change signature animations — how far toward "game" do we
   push (screen shake, confetti on victory, speed lines)?
5. Light mode outside the race flow, or a fully dark, arcade-feeling app?

---

*Reference: the current functional implementation lives in
`ios/GhostRace/Views/` (HomeView, RecordView, SegmentDetailView,
ChallengeAcceptView, RaceView incl. TrackBar/Countdown/Result), with race phases
and data in `RaceViewModel.swift` and domain events in
`GhostRaceKit/Sources/GhostRaceKit/` (GhostEngine emits gap/lead-change/final-
stretch events; RaceCueScheduler rate-limits cues). All copy quoted above is live
in the code and can be treated as approved voice/tone reference.*
