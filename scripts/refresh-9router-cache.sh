#!/usr/bin/env bash
# Refresh the pi-9router-ext discovery cache.
#
# pi-9router-ext serves models from ~/.cache/pi/9router-discovery-cache.json and
# never invalidates that snapshot by age. Its own background refresh is capped at
# STARTUP_DISCOVERY_TIMEOUT_MS=5000 (src/index.ts), but this router's /v1/models
# takes ~10s, so the refresh always aborts and the snapshot never self-heals.
# Newly added upstream models therefore stay invisible -- most visibly in paseo,
# which builds its catalog from a short-lived `pi --mode rpc` process.
#
# Safe to run at any time: writes to a temp file and renames, so a concurrent pi
# never observes a half-written cache. Preserves webRoutes and the credential
# fingerprint the extension validates against.
set -euo pipefail

CONFIG="${HOME}/.pi/agent/9router-config.json"
CACHE="${XDG_CACHE_HOME:-${HOME}/.cache}/pi/9router-discovery-cache.json"

if [[ ! -f "$CONFIG" ]]; then
  echo "error: $CONFIG not found; nothing to refresh" >&2
  exit 1
fi

mkdir -p "$(dirname "$CACHE")"

export CONFIG_PATH="$CONFIG" CACHE_PATH="$CACHE"

node --input-type=module -e '
import { readFileSync, writeFileSync, renameSync } from "node:fs";
import { createHash } from "node:crypto";

const config = JSON.parse(readFileSync(process.env.CONFIG_PATH, "utf8"));
if (!config.baseUrl) throw new Error("9router-config.json has no baseUrl");
if (!config.apiKey) throw new Error("9router-config.json has no apiKey");

const cachePath = process.env.CACHE_PATH;
// A missing cache is fine -- the extension creates one on first discovery.
let webRoutes;
try { webRoutes = JSON.parse(readFileSync(cachePath, "utf8")).webRoutes; }
catch { webRoutes = undefined; }

const url = config.baseUrl.replace(/\/+$/, "") + "/v1/models";
const res = await fetch(url, {
  headers: { Accept: "application/json", Authorization: `Bearer ${config.apiKey}` },
  signal: AbortSignal.timeout(60_000),
});
if (!res.ok) throw new Error(`9router returned ${res.status}: ${await res.text().catch(() => "")}`);

const body = await res.json();
const models = Array.isArray(body.data) ? body.data : [];
if (models.length === 0) throw new Error("9router returned no models; keeping existing cache");

writeFileSync(cachePath + ".new", JSON.stringify({
  apiKeyHash: "sha256:" + createHash("sha256").update(config.apiKey).digest("hex"),
  baseUrl: config.baseUrl,
  models,
  ts: Date.now(),
  ...(webRoutes ? { webRoutes } : {}),
}));
renameSync(cachePath + ".new", cachePath);
console.log(`wrote ${models.length} models to ${cachePath}`);
'

echo
echo "Note: restart the paseo daemon (or force a catalog refresh in the app) —"
echo "it caches the model catalog per workspace and will not re-poll pi on its own."
