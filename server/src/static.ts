import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { extname, join, normalize, resolve, sep } from "node:path";
import type { IncomingMessage, ServerResponse } from "node:http";

const CONTENT_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".gpx": "application/gpx+xml; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
};

/**
 * Serve a file from `rootDir` for a GET/HEAD request. Returns true if it wrote
 * a response (found the file, or fell back to index.html for an extension-less
 * path), false if the caller should keep handling the request (e.g. hand it to
 * the API/404 path). Guards against path traversal outside `rootDir`.
 */
export async function serveStatic(
  req: IncomingMessage,
  res: ServerResponse,
  rootDir: string,
): Promise<boolean> {
  const root = resolve(rootDir);
  const url = new URL(req.url ?? "/", "http://localhost");
  let pathname = decodeURIComponent(url.pathname);
  if (pathname.endsWith("/")) pathname += "index.html";

  const target = normalize(join(root, pathname));
  if (target !== root && !target.startsWith(root + sep)) return false; // traversal attempt

  const file = await statFile(target);
  if (file) return sendFile(req, res, target, file.size);

  // SPA-style fallback: an extension-less unknown path serves the shell.
  if (extname(pathname) === "") {
    const index = join(root, "index.html");
    const indexStat = await statFile(index);
    if (indexStat) return sendFile(req, res, index, indexStat.size);
  }
  return false;
}

async function statFile(path: string): Promise<{ size: number } | null> {
  try {
    const s = await stat(path);
    return s.isFile() ? { size: s.size } : null;
  } catch {
    return null;
  }
}

function sendFile(req: IncomingMessage, res: ServerResponse, path: string, size: number): boolean {
  res.writeHead(200, {
    "content-type": CONTENT_TYPES[extname(path)] ?? "application/octet-stream",
    "content-length": size,
    "cache-control": "no-cache",
  });
  if (req.method === "HEAD") {
    res.end();
    return true;
  }
  createReadStream(path).pipe(res);
  return true;
}
