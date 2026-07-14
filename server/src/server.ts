import { createServer, type Server } from "node:http";
import { openDb, type Db } from "./db.js";
import { createRequestHandler } from "./api.js";
import { serveStatic } from "./static.js";
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
  /** Directory to serve the web client from. Static serving is off when unset. */
  webDir?: string;
}

export function createGhostRaceServer(opts: GhostRaceServerOptions = {}): GhostRaceServer {
  const db = openDb(opts.dbPath ?? ":memory:");
  const rooms = new RaceRoomManager(opts.race ?? {});
  const handler = createRequestHandler(db, rooms);
  const webDir = opts.webDir;
  const server = createServer((req, res) => {
    // The web client shares this origin so there's no CORS. Anything under
    // /api stays with the JSON handler; other GET/HEAD requests try the static
    // web build first and fall through to the API 404 if there's no such file.
    const isApi = new URL(req.url ?? "/", "http://localhost").pathname.startsWith("/api/");
    if (webDir && !isApi && (req.method === "GET" || req.method === "HEAD")) {
      serveStatic(req, res, webDir)
        .then((served) => {
          if (!served) void handler(req, res);
        })
        .catch(() => void handler(req, res));
      return;
    }
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
