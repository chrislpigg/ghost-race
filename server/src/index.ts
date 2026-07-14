import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { createGhostRaceServer } from "./server.js";

const port = Number(process.env.PORT ?? 8787);
const dbPath = process.env.GHOSTRACE_DB ?? "ghostrace.sqlite";
// Compiled to server/dist/src/index.js, so the repo's web/ is three levels up.
const here = dirname(fileURLToPath(import.meta.url));
const webDir = process.env.GHOSTRACE_WEB ?? resolve(here, "../../../web");

const app = createGhostRaceServer({ dbPath, webDir });
app
  .listen(port)
  .then((boundPort) => {
    console.log(`GhostRace server listening on http://0.0.0.0:${boundPort} (db: ${dbPath})`);
  })
  .catch((err) => {
    console.error("failed to start", err);
    process.exit(1);
  });
