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
  mcp.json             # Pi-global MCP servers (next-devtools, …)
  extensions/
agents-skills/         # → ~/.agents/skills
auth/
  auth.json.example
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

Project-local overrides (not managed by this repo) can still use `.mcp.json` or
`.pi/mcp.json` in an app checkout; Pi-project `.pi/mcp.json` wins for
enable/disable flags.

## Auth

See `auth/auth.json.example`. Real credentials stay only on each machine under `~/.pi/agent/auth.json`.

Providers used in this setup:

- **kie** — API key (Grok 4.5, GPT-5.6 family, Gemini 3.6 Flash OpenAI + native Gemini body)
- **opencode** / **opencode-go** — API key
- **openai-codex** — OAuth via `/login`

Native Kie Gemini (`kie/gemini-3-6-flash`, `google-generative-ai`) needs the
`agent/extensions/kie-gemini-compat.ts` extension: Kie requires Bearer auth and
sends SSE `[DONE]` without `finishReason`, which pi’s Google adapter does not
handle alone.

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
