# my-pi-dotfiles

Portable [Pi](https://pi.dev) setup: settings, models, local extensions, skills, and package pins.

[![ci](https://github.com/Tugeru/my-pi-dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/Tugeru/my-pi-dotfiles/actions/workflows/ci.yml)

Daily sync is **git**, not manual copying. On this machine, managed files are **symlinked** from the repo into Pi’s config dirs, so edits in Pi are already in git.

## What this manages

| Path in repo | Installs to |
|--------------|-------------|
| `agent/settings.json` | `~/.pi/agent/settings.json` |
| `agent/models.json` | `~/.pi/agent/models.json` |
| `agent/mcp.json` | `~/.pi/agent/mcp.json` |
| `agent/extensions/*` | `~/.pi/agent/extensions/*` |
| `agents-skills/<name>/` | `~/.agents/skills/<name>/` |

Packages (from `settings.json`):

- `npm:pi-subagents@0.46.0`
- `npm:pi-web-access@0.21.0`
- `git:github.com/kotarac/pi-fetch@v2.0.0`
- `npm:pi-mcp-adapter@2.22.0`
- `npm:context-mode`
- `npm:pi-hashline-edit-pro@2.5.3` — disables built-in `edit`; use hash-anchored `read` / `replace` / `undo_last_replace`
- `npm:pi-token-count@0.1.2` — footer: `tokens | %/window used | $ spent | model/reasoning`

MCP servers (from `agent/mcp.json`, via `pi-mcp-adapter`):

- `next-devtools` → `npx -y next-devtools-mcp@0.4.0` (lazy; needs Next.js 16+ `npm run dev` for runtime tools)

## Never tracked

- `auth.json` / API keys / OAuth tokens
- `sessions/`, `missions/`, `run-history.jsonl`
- `models-store.json`, `trust.json`
- `npm/`, `git/` package install trees

## New machine

```bash
git clone <this-repo> ~/my-pi-dotfiles
cd ~/my-pi-dotfiles
./install.sh --pi-install          # install pi CLI if needed
# or, if pi is already installed:
./install.sh
```

Then authenticate once:

```bash
pi
# /login  → Codex / providers as needed
# or copy auth/auth.json.example → ~/.pi/agent/auth.json and fill keys
```

### Options

```bash
./install.sh --mode symlink|copy
./install.sh --profile full|minimal|orca
./install.sh --no-orca
./install.sh --skip-packages
./install.sh --dry-run
./install.sh --doctor
```

`--dry-run` prints every action as `would: <command>` without touching the system, then ends
with a summary of what would change vs. what is already up to date. Safe to run anytime, also
with `--pi-install` on a machine without pi.

## Day-to-day workflow

**This machine (symlinks):**

1. Change settings/models/extensions/skills as usual (Pi or editor).
2. Because paths are symlinked, the repo already has the change.
3. Commit and push:

```bash
cd ~/orca/projects/my-pi-dotfiles   # or your clone path
git status
git diff
git add -p
git commit -m "chore: update pi defaults"
git push
```

**Other machine:**

```bash
git pull
./install.sh
```

**If a symlink was replaced by a regular file** (or you edited live config before linking):

```bash
./scripts/sync-from-live.sh
git diff
# commit the imported changes, then:
./install.sh --force
```

## Layout

```text
agent/                 # → ~/.pi/agent
  settings.json
  models.json
  mcp.json             # Pi-global MCP servers (composio, …)
  extensions/
agents-skills/         # → ~/.agents/skills
auth/
  auth.json.example
  composio.env.example
profiles/              # full | minimal | orca
scripts/
  doctor.sh
  sync-from-live.sh
install.sh
```

## MCP / Next.js DevTools

Pi has no built-in MCP. This setup uses `pi-mcp-adapter` plus a tracked
`agent/mcp.json`.

After install (or after editing `mcp.json`):

1. Restart Pi, or run `/reload`
2. Check status: `/mcp` or `mcp({})`
3. In a Next.js 16+ app, start the dev server (`npm run dev`)
4. Discover runtime tools: `mcp({ tool: "nextjs_index" })` then
   `mcp({ tool: "nextjs_call", args: { port: 3000, toolName: "get_errors" } })`

`nextjs_docs` and `browser_eval` work without a running dev server.
`browser_eval` only guides setup of `agent-browser`; it does not drive a browser.

Telemetry from next-devtools is disabled via `NEXT_TELEMETRY_DISABLED=1` in
`agent/mcp.json`.

## Models / 9router overrides

`pi-9router-ext` registers 9router models dynamically and trusts whatever the
router's `/v1/models` reports. The router reports `272000` for every `cx/*`
route, which is OpenAI's *long-context pricing threshold*, not a limit. Fix
individual models in `agent/models.json` with `modelOverrides` — that layer is
applied last, after the extension's dynamic registration, so it always wins:

```json
"modelOverrides": {
  "cx/gpt-6-luna": { "name": "GPT-6 Luna (9router cx)", "contextWindow": 400000, "maxTokens": 128000 },
  "cx/gpt-6-sol":  { "name": "GPT-6 Sol (9router cx)",  "contextWindow": 400000, "maxTokens": 128000 }
}
```

Measured against the live route (2026-09-28): a 902k-token prompt succeeds,
930k fails with `finish_reason: "failed"`. OpenAI's published spec for both
`gpt-6-luna` and `gpt-6-sol` is 1,050,000 total context, 922,000 max input,
128,000 max output. The tracked value is the conservative 400k; raise it to
`1050000` if you want to use the full window.

### Thinking effort

Both models take `reasoning_effort` = `none`, `low`, `medium`, `high`,
`xhigh`, `max` (`medium` is the upstream default; `minimal` is not a valid
OpenAI value). Verified live: completion token counts scale with the requested
effort, and tool calls succeed at every level, including `high`/`xhigh`/`max`.

`pi-9router-ext` omits `max` from its map, which makes pi hide that level
entirely (`getSupportedThinkingLevels` requires the key to be present for
`xhigh`/`max`). The overrides restore all six levels and hide `minimal` by
mapping it to `null`, which is the only way to remove a level from the picker:

```json
"thinkingLevelMap": {
  "off": "none", "minimal": null, "low": "low", "medium": "medium",
  "high": "high", "xhigh": "xhigh", "max": "max"
}
```

`thinkingFormat: "openai"` has no dedicated branch in pi-ai; it falls through to
the generic path at `api/openai-completions.js:657`, which sends
`reasoning_effort = map[level] ?? level`, or `map.off` when thinking is off.
Note the `??`: mapping a level to `null` does not suppress the request, it only
hides the level from the picker. Never map a level to a string the upstream
model does not accept.

### `oc/muse-spark-1.3-contributor-free`

A static entry, not a `modelOverride`: the `oc/` free route is absent from the
router's `/v1/models` (1,896 ids, no `oc/` muse-spark), so the extension never
registers it. Requests to the id work anyway, which is why a static entry is
required.

```json
{
  "id": "oc/muse-spark-1.3-contributor-free",
  "name": "Muse Spark 1.3 Free (9router)",
  "api": "openai-completions",
  "contextWindow": 400000,
  "maxTokens": 131072,
  "thinkingLevelMap": {
    "off": null, "minimal": "minimal", "low": "low", "medium": "medium",
    "high": "high", "xhigh": "xhigh", "max": "max"
  }
}
```

`"off": null` is mandatory and opposite to the `cx/` models: Muse Spark rejects
`reasoning_effort: "none"` with **HTTP 400** because reasoning is mandatory.
Mapping `off` to `"none"` would make every off-level request fail, so the level
is hidden and pi clamps it up to `minimal`. `minimal` *is* valid here, unlike
OpenAI models.

Measured on this route (2026-09-28):

- **Streaming is required.** A non-streaming `chat/completions` call returns
  `HTTP 200`, `finish_reason: "in_progress"` and zero usage — a phantom
  success. Every response must be verified with a real streaming call.
- The provider rejects `max_tokens < 16` with HTTP 400, so context probes that
  use a tiny output budget fail for the wrong reason.
- Reasoning effort is honored: reasoning characters grew 195 → 335 → 451 → 523
  → 571 across `minimal` → `max` on an identical prompt.
- Tool calls work at every level (`stop=toolUse`, correct name and arguments).
- `contextWindow` is 400000 rather than the documented 1,048,576 because the
  route caps HTTP bodies at ~3MB: 2.97MB is accepted, 3.08MB returns
  `413 FUNCTION_PAYLOAD_TOO_LARGE`. At pi's chars/4 estimate that is roughly
  700k tokens of headroom, so a 1,048,576 setting would build requests the
  router refuses. The 1,048,576 figure is vendor-documented, not measured — the
  route reports no token usage, so the model limit itself is unmeasurable here.

Two related notes: `providers.9router.baseUrl` pointed at
`http://localhost:20128/v1`, where nothing was listening, so every static
`9router` model was dead; it now points at the same endpoint
`pi-9router-ext` uses. `oc/x-preview-f-free` in the same provider returns
`401 Model x-preview-f-free is not supported` and should be deleted.

Project-local overrides (not managed by this repo) can still use `.mcp.json` or
`.pi/mcp.json` in an app checkout; Pi-project `.pi/mcp.json` wins for
enable/disable flags.

## MCP / Composio

`agent/mcp.json` registers Composio's hosted MCP endpoint, which exposes
1000+ app integrations through a small set of meta-tools
(`COMPOSIO_SEARCH_TOOLS`, `COMPOSIO_CONNECT`, `COMPOSIO_EXECUTE`).

You supply one credential. `agent/mcp.json` reads it with an inline shell
command, so no key is ever committed:

1. Get the key at <https://app.composio.dev> → For You → Connect → Settings →
   Sessions & API Key. It looks like `ck_…`.
2. Store it, either way:

   ```bash
   mkdir -p ~/.config/composio
   printf '%s' 'ck_REPLACE_ME' > ~/.config/composio/api-key
   chmod 600 ~/.config/composio/api-key
   # ...or export it in your shell profile:
   export COMPOSIO_CONNECT_API_KEY='ck_REPLACE_ME'
   ```

3. `/reload`, then check: `mcp({})` or `/mcp`.

The header command checks `COMPOSIO_CONNECT_API_KEY` first, then falls back to
`~/.config/composio/api-key`. If neither is present, connecting fails with
`command exited with code 1`.

`composio-platform` is a second, `disabled` entry for the developer (Platform)
flow. To use it, create a session with MCP enabled, paste `session.mcp.url` over
`REPLACE_ME_SESSION_MCP_URL`, write the `ak_…` project key to
`~/.config/composio/platform-api-key`, and set `"disabled": false`.

Note: the old `https://mcp.composio.dev/...` URLs from older tutorials are
dead — that endpoint was removed. Use the entry above.

## Auth

See `auth/auth.json.example`. Real credentials stay only on each machine under `~/.pi/agent/auth.json`.

Providers used in this setup:

- **kie** — API key (Grok 4.5, GPT-5.6 family, Gemini 3.6 Flash OpenAI + native Gemini body)
- **opencode** / **opencode-go** — API key
- **openai-codex** — OAuth via `/login`

Native Kie Gemini (`kie/gemini-3-6-flash-google`, `kie/gemini-3-7-flash-google`, `google-generative-ai`) needs the
`agent/extensions/kie-gemini-compat.ts` extension: Kie requires Bearer auth, sends
SSE `[DONE]` without `finishReason`, and routes by API model name (the pi-facing
`-google` id is rewritten to the API id, e.g. `gemini-3-7-flash-google` →
`gemini-3-7-flash`) — none of which pi’s Google adapter handles alone.

`agent/extensions/persistent-error-retry.ts` keeps working after provider/system
errors Pi does not auto-retry (for example Kie GPT-5.6 Sol `Unexpected end of
JSON input`). After built-in retries settle, it waits 2s and resumes until the
turn succeeds, the user aborts (Esc), or `/persistent-retry off`.

## CI / local checks

GitHub Actions runs on every push and PR:

- ShellCheck on `install.sh` and `scripts/*.sh`
- JSON + structure validation (`scripts/ci-check.sh`)
- Gitleaks secret scan
- Isolated `install.sh` smoke tests (copy + symlink, full/minimal/`--no-orca`)

Run the same static checks locally:

```bash
./scripts/ci-check.sh
shellcheck install.sh scripts/*.sh   # if shellcheck is installed
./install.sh --dry-run --skip-packages
```

Package installs and live model calls are intentionally **not** required in CI.
