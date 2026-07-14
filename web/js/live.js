/**
 * WebSocket client for live races. Mirrors the message protocol in
 * server/src/ws.ts / race-room.ts (and LiveRaceClient.swift). Emits normalized
 * events via `.on(name, cb)`.
 */
export class LiveRaceClient {
  constructor(raceId, deviceToken) {
    this.raceId = raceId;
    this.deviceToken = deviceToken;
    this.ws = null;
    this.handlers = {};
  }

  on(event, cb) {
    this.handlers[event] = cb;
    return this;
  }

  emit(event, payload) {
    this.handlers[event]?.(payload);
  }

  connect() {
    const url = new URL("/ws", location.href);
    url.protocol = location.protocol === "https:" ? "wss:" : "ws:";
    this.ws = new WebSocket(url);
    this.ws.onopen = () =>
      this.send({ type: "join", raceId: this.raceId, deviceToken: this.deviceToken });
    this.ws.onmessage = (ev) => this.handle(ev.data);
    this.ws.onclose = () => this.emit("socketClosed");
    this.ws.onerror = () => {};
  }

  send(obj) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(obj));
  }

  ready() {
    this.send({ type: "ready" });
  }

  sendPosition(t, d) {
    this.send({ type: "pos", t, d });
  }

  finish(durationS) {
    this.send({ type: "finish", durationS });
  }

  close() {
    if (this.ws) {
      this.ws.onclose = null;
      this.ws.close();
      this.ws = null;
    }
  }

  handle(text) {
    let m;
    try {
      m = JSON.parse(text);
    } catch {
      return;
    }
    switch (m.type) {
      case "joined":
        this.emit("joined", { you: m.you ?? "", peers: m.peers ?? [] });
        break;
      case "peer_joined":
        this.emit("peerJoined", { name: m.name ?? "Rival" });
        break;
      case "countdown":
        this.emit("countdown", { startAtMs: m.startAt, serverNowMs: m.serverNow });
        break;
      case "pos":
        this.emit("opponentPosition", { t: m.t, d: m.d });
        break;
      case "peer_finished":
        this.emit("opponentFinished", { durationS: m.durationS ?? 0 });
        break;
      case "result":
        this.emit("result", { winnerId: m.winnerId ?? "", reason: m.reason ?? "finish", times: m.times ?? {} });
        break;
      case "peer_disconnected":
        this.emit("opponentDisconnected", { graceMs: m.graceMs ?? 0 });
        break;
      case "peer_reconnected":
        this.emit("opponentReconnected", {});
        break;
      case "error":
        this.emit("error", { message: m.message ?? "unknown error" });
        break;
      default:
        break;
    }
  }
}
