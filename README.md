# my-pi-dotfiles

Portable [Pi](https://pi.dev) setup: settings, models, local extensions, skills, and package pins.

[![ci](https://github.com/Tugeru/my-pi-dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/Tugeru/my-pi-dotfiles/actions/workflows/ci.yml)

Daily sync is **git**, not manual copying. On this machine, managed files are **symlinked** from the repo into Pi’s config dirs, so edits in Pi are already in git.

## What this manages

| Path in repo | Installs to |
|--------------|-------------|
| `agent/settings.json` | `~/.pi/agent/settings.json` |
| `agent/models.json` | `~/.pi/agent/models.json` |
| `agent/extensions/*` | `~/.pi/agent/extensions/*` |
| `agents-skills/<name>/` | `~/.agents/skills/<name>/` |

Packages (from `settings.json`):

- `npm:pi-subagents@0.46.0`
- `npm:pi-web-access@0.21.0`
- `git:github.com/kotarac/pi-fetch@v2.0.0`

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

## Auth

See `auth/auth.json.example`. Real credentials stay only on each machine under `~/.pi/agent/auth.json`.

Providers used in this setup:

- **kie** — API key
- **opencode** / **opencode-go** — API key
- **openai-codex** — OAuth via `/login`

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
