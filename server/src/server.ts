import { createServer, type Server } from "node:http";
import { openDb, type Db } from "./db.js";
import { createRequestHandler } from "./api.js";
import { RaceRoomManager, type RaceRoomOptions } from "./race-room.js";
import { attachRaceSockets } from "./ws.js";
import type { WebSocketServer } from "ws";

export interface GhostRaceServer {
  server: Server;
  wss: WebSocketServer;
  db: Db;
  rooms: RaceRoomManager;
  listen(port: number): Promise<number>; // resolves with the bound port
  close(): Promise<void>;
}

export interface GhostRaceServerOptions {
  dbPath?: string;
  race?: Pick<RaceRoomOptions, "countdownMs" | "graceMs">;
}

export function createGhostRaceServer(opts: GhostRaceServerOptions = {}): GhostRaceServer {
  const db = openDb(opts.dbPath ?? ":memory:");
  const rooms = new RaceRoomManager(opts.race ?? {});
  const handler = createRequestHandler(db, rooms);
  const server = createServer((req, res) => {
    void handler(req, res);
  });
  const wss = attachRaceSockets(server, db, rooms);

  return {
    server,
    wss,
    db,
    rooms,
    listen(port: number): Promise<number> {
      return new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(port, () => {
          const address = server.address();
          resolve(typeof address === "object" && address ? address.port : port);
        });
      });
    },
    close(): Promise<void> {
      return new Promise((resolve) => {
        for (const client of wss.clients) client.terminate();
        wss.close(() => {
          server.close(() => {
            db.close();
            resolve();
          });
        });
      });
    },
  };
}
