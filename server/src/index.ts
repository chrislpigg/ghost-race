import { createGhostRaceServer } from "./server.js";

const port = Number(process.env.PORT ?? 8787);
const dbPath = process.env.GHOSTRACE_DB ?? "ghostrace.sqlite";

const app = createGhostRaceServer({ dbPath });
app
  .listen(port)
  .then((boundPort) => {
    console.log(`GhostRace server listening on http://0.0.0.0:${boundPort} (db: ${dbPath})`);
  })
  .catch((err) => {
    console.error("failed to start", err);
    process.exit(1);
  });
