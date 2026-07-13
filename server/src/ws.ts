import type { Server } from "node:http";
import { WebSocketServer, WebSocket } from "ws";
import type { Db } from "./db.js";
import * as store from "./store.js";
import type { Peer, RaceRoomManager, ServerMsg } from "./race-room.js";

/**
 * Client -> server messages. The first message on a fresh socket must be
 * `join`; after that the socket is bound to one racer in one room.
 */
type ClientMsg =
  | { type: "join"; raceId: string; deviceToken: string }
  | { type: "ready" }
  | { type: "pos"; t: number; d: number }
  | { type: "finish"; durationS: number };

export function attachRaceSockets(server: Server, db: Db, rooms: RaceRoomManager): WebSocketServer {
  const wss = new WebSocketServer({ server, path: "/ws" });

  wss.on("connection", (socket: WebSocket) => {
    let userId: string | null = null;
    let raceId: string | null = null;

    socket.on("message", (data) => {
      let msg: ClientMsg;
      try {
        msg = JSON.parse(String(data)) as ClientMsg;
      } catch {
        send(socket, { type: "error", message: "invalid JSON" });
        return;
      }

      if (msg.type === "join") {
        const user = store.getUserByToken(db, msg.deviceToken ?? "");
        if (!user) {
          send(socket, { type: "error", message: "unknown device token" });
          socket.close();
          return;
        }
        const room = rooms.get(msg.raceId ?? "");
        if (!room) {
          send(socket, { type: "error", message: "race not found" });
          socket.close();
          return;
        }
        userId = user.id;
        raceId = room.raceId;
        const peer: Peer = {
          userId: user.id,
          name: user.name,
          send: (m: ServerMsg) => send(socket, m),
        };
        room.join(peer);
        return;
      }

      if (!userId || !raceId) {
        send(socket, { type: "error", message: "join first" });
        return;
      }
      const room = rooms.get(raceId);
      if (!room) {
        send(socket, { type: "error", message: "race is over" });
        return;
      }
      switch (msg.type) {
        case "ready":
          room.ready(userId);
          break;
        case "pos":
          room.position(userId, Number(msg.t), Number(msg.d));
          break;
        case "finish":
          room.finish(userId, Number(msg.durationS));
          break;
        default:
          send(socket, { type: "error", message: "unknown message type" });
      }
    });

    socket.on("close", () => {
      if (userId && raceId) rooms.get(raceId)?.disconnect(userId);
    });
  });

  return wss;
}

function send(socket: WebSocket, msg: ServerMsg): void {
  if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(msg));
}
