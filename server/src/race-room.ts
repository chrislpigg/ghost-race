/**
 * Live race room state machine. Socket-agnostic: peers are anything with a
 * `send` function, so tests can drive rooms with fake peers and the WS layer
 * just adapts sockets onto this interface.
 *
 * Lifecycle: waiting -> countdown -> racing -> finished | abandoned
 *
 * The opponent's positions relayed here feed the same GhostEngine on the
 * client that ghost mode uses — a live rival is just a ghost arriving in
 * real time.
 */

export interface Peer {
  userId: string;
  name: string;
  send(msg: ServerMsg): void;
}

export type ServerMsg =
  | { type: "joined"; raceId: string; you: string; peers: Array<{ userId: string; name: string }> }
  | { type: "peer_joined"; userId: string; name: string }
  | { type: "peer_ready"; userId: string }
  | { type: "countdown"; startAt: number; serverNow: number }
  | { type: "pos"; userId: string; t: number; d: number }
  | { type: "peer_finished"; userId: string; durationS: number }
  | { type: "result"; winnerId: string; reason: "finish" | "dnf"; times: Record<string, number | null> }
  | { type: "peer_disconnected"; userId: string; graceMs: number }
  | { type: "peer_reconnected"; userId: string }
  | { type: "peer_left"; userId: string }
  | { type: "error"; message: string };

export type RoomState = "waiting" | "countdown" | "racing" | "finished" | "abandoned";

export interface RaceRoomOptions {
  /** Delay between both-ready and the shared race start timestamp. */
  countdownMs?: number;
  /** How long a racer may be disconnected mid-race before they DNF. */
  graceMs?: number;
  now?: () => number;
  onResult?: (result: {
    raceId: string;
    winnerId: string;
    loserId: string;
    winnerTimeS: number | null;
    loserTimeS: number | null;
    reason: "finish" | "dnf";
  }) => void;
}

interface Racer {
  peer: Peer;
  ready: boolean;
  finishedS: number | null;
  connected: boolean;
  graceTimer: NodeJS.Timeout | null;
}

export class RaceRoom {
  readonly raceId: string;
  readonly segmentId: string | null;
  private readonly countdownMs: number;
  private readonly graceMs: number;
  private readonly now: () => number;
  private readonly onResult?: RaceRoomOptions["onResult"];

  private racers = new Map<string, Racer>();
  state: RoomState = "waiting";
  startAt: number | null = null;

  constructor(raceId: string, segmentId: string | null, opts: RaceRoomOptions = {}) {
    this.raceId = raceId;
    this.segmentId = segmentId;
    this.countdownMs = opts.countdownMs ?? 10_000;
    this.graceMs = opts.graceMs ?? 30_000;
    this.now = opts.now ?? Date.now;
    this.onResult = opts.onResult;
  }

  join(peer: Peer): void {
    const existing = this.racers.get(peer.userId);
    if (existing) {
      this.reconnect(peer, existing);
      return;
    }
    if (this.racers.size >= 2) {
      peer.send({ type: "error", message: "race is full" });
      return;
    }
    if (this.state !== "waiting") {
      peer.send({ type: "error", message: "race already started" });
      return;
    }
    this.racers.set(peer.userId, {
      peer,
      ready: false,
      finishedS: null,
      connected: true,
      graceTimer: null,
    });
    peer.send({
      type: "joined",
      raceId: this.raceId,
      you: peer.userId,
      peers: [...this.racers.values()].map((r) => ({
        userId: r.peer.userId,
        name: r.peer.name,
      })),
    });
    this.broadcast({ type: "peer_joined", userId: peer.userId, name: peer.name }, peer.userId);
  }

  ready(userId: string): void {
    const racer = this.racers.get(userId);
    if (!racer || this.state !== "waiting") return;
    racer.ready = true;
    this.broadcast({ type: "peer_ready", userId }, userId);
    const all = [...this.racers.values()];
    if (all.length === 2 && all.every((r) => r.ready)) {
      this.state = "countdown";
      this.startAt = this.now() + this.countdownMs;
      this.broadcast({ type: "countdown", startAt: this.startAt, serverNow: this.now() });
      setTimeout(() => {
        if (this.state === "countdown") this.state = "racing";
      }, this.countdownMs).unref?.();
    }
  }

  position(userId: string, t: number, d: number): void {
    if (this.state !== "racing" && this.state !== "countdown") return;
    if (!this.racers.has(userId)) return;
    this.broadcast({ type: "pos", userId, t, d }, userId);
  }

  finish(userId: string, durationS: number): void {
    const racer = this.racers.get(userId);
    if (!racer || (this.state !== "racing" && this.state !== "countdown")) return;
    if (racer.finishedS !== null) return;
    racer.finishedS = durationS;
    this.broadcast({ type: "peer_finished", userId, durationS }, userId);
    const all = [...this.racers.values()];
    if (all.every((r) => r.finishedS !== null)) {
      this.settle("finish");
    }
  }

  disconnect(userId: string): void {
    const racer = this.racers.get(userId);
    if (!racer) return;
    racer.connected = false;
    if (this.state === "waiting") {
      this.racers.delete(userId);
      this.broadcast({ type: "peer_left", userId });
      return;
    }
    if (this.state === "finished" || this.state === "abandoned") return;
    if (racer.finishedS !== null) return; // already finished; nothing at stake
    this.broadcast({ type: "peer_disconnected", userId, graceMs: this.graceMs }, userId);
    racer.graceTimer = setTimeout(() => {
      if (!racer.connected && racer.finishedS === null) {
        this.settle("dnf", userId);
      }
    }, this.graceMs);
    racer.graceTimer.unref?.();
  }

  private reconnect(peer: Peer, racer: Racer): void {
    racer.peer = peer; // fresh socket
    racer.connected = true;
    if (racer.graceTimer) {
      clearTimeout(racer.graceTimer);
      racer.graceTimer = null;
    }
    peer.send({
      type: "joined",
      raceId: this.raceId,
      you: peer.userId,
      peers: [...this.racers.values()].map((r) => ({
        userId: r.peer.userId,
        name: r.peer.name,
      })),
    });
    if (this.state === "countdown" || this.state === "racing") {
      if (this.startAt !== null) {
        peer.send({ type: "countdown", startAt: this.startAt, serverNow: this.now() });
      }
    }
    this.broadcast({ type: "peer_reconnected", userId: peer.userId }, peer.userId);
  }

  /** Decide the winner and close the room. `dnfUserId` loses by abandonment. */
  private settle(reason: "finish" | "dnf", dnfUserId?: string): void {
    if (this.state === "finished" || this.state === "abandoned") return;
    const all = [...this.racers.entries()];
    if (all.length < 2) {
      this.state = "abandoned";
      return;
    }
    const [[idA, a], [idB, b]] = all as [[string, Racer], [string, Racer]];
    let winnerId: string;
    let loserId: string;
    if (reason === "dnf") {
      loserId = dnfUserId!;
      winnerId = loserId === idA ? idB : idA;
    } else {
      const aTime = a.finishedS ?? Number.POSITIVE_INFINITY;
      const bTime = b.finishedS ?? Number.POSITIVE_INFINITY;
      winnerId = aTime <= bTime ? idA : idB;
      loserId = winnerId === idA ? idB : idA;
    }
    this.state = "finished";
    for (const [, r] of all) {
      if (r.graceTimer) clearTimeout(r.graceTimer);
    }
    const times: Record<string, number | null> = {
      [idA]: a.finishedS,
      [idB]: b.finishedS,
    };
    this.broadcast({ type: "result", winnerId, reason, times });
    this.onResult?.({
      raceId: this.raceId,
      winnerId,
      loserId,
      winnerTimeS: this.racers.get(winnerId)?.finishedS ?? null,
      loserTimeS: this.racers.get(loserId)?.finishedS ?? null,
      reason,
    });
  }

  private broadcast(msg: ServerMsg, exceptUserId?: string): void {
    for (const racer of this.racers.values()) {
      if (racer.peer.userId === exceptUserId) continue;
      if (!racer.connected) continue;
      racer.peer.send(msg);
    }
  }
}

export class RaceRoomManager {
  private rooms = new Map<string, RaceRoom>();
  constructor(private readonly opts: RaceRoomOptions = {}) {}

  create(raceId: string, segmentId: string | null, onResult?: RaceRoomOptions["onResult"]): RaceRoom {
    const room = new RaceRoom(raceId, segmentId, {
      ...this.opts,
      onResult: (r) => {
        (onResult ?? this.opts.onResult)?.(r);
        // Room is done; let it be garbage collected.
        this.rooms.delete(raceId);
      },
    });
    this.rooms.set(raceId, room);
    return room;
  }

  get(raceId: string): RaceRoom | undefined {
    return this.rooms.get(raceId);
  }
}
