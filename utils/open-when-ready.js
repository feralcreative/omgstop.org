// Opens the site in a browser once `npm start` is serving.
//
// This lives outside the Eleventy process on purpose. `npm start` runs Eleventy
// with `--serve`, which watches src/ and rebuilds on every save — an opener
// wired into the server would risk a new tab on each restart. Run once per
// `npm start` instead, alongside the server, and exit as soon as the port
// answers.
//
// Set OPEN_BROWSER=0 to skip.

import { spawn } from "node:child_process";

const PORT = process.env.PORT || "8066";
const URL = `http://localhost:${PORT}/`;
const TIMEOUT_MS = 20000;
const POLL_MS = 250;

if (process.env.OPEN_BROWSER === "0") process.exit(0);

const opener =
  process.platform === "darwin" ? ["open", [URL]]
  : process.platform === "win32" ? ["cmd", ["/c", "start", "", URL]]
  : ["xdg-open", [URL]];

// Any HTTP response means the server is up. A 404 counts just as much as a 200
// — the first build may not have written index.html yet.
async function isUp() {
  try {
    await fetch(URL, { signal: AbortSignal.timeout(POLL_MS * 2) });
    return true;
  } catch {
    return false;
  }
}

const deadline = Date.now() + TIMEOUT_MS;
while (Date.now() < deadline) {
  if (await isUp()) {
    console.log(`\n  omgstop.org → ${URL}\n`);
    spawn(opener[0], opener[1], { stdio: "ignore", detached: true }).unref();
    process.exit(0);
  }
  await new Promise((r) => setTimeout(r, POLL_MS));
}

console.warn(`[open] Server did not answer within ${TIMEOUT_MS / 1000}s; open ${URL} yourself.`);
