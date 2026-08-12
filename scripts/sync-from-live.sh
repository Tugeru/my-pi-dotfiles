#!/usr/bin/env bash
# Copy managed live Pi config back into this repo (allowlisted paths only).
# Use when live files drifted (e.g. symlink broken) or to adopt new files.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
AGENTS_SKILLS_DIR="${PI_AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"
DRY_RUN=0

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done

copy_file() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || { log "skip missing $src"; return 0; }
  # Do not follow into repo if src is already our symlink
  if [[ -L "$src" ]]; then
    local target
    target="$(readlink "$src")"
    if [[ "$target" == "$dest" ]]; then
      log "ok already linked $src"
      return 0
    fi
  fi
  log "import $src -> $dest"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

copy_dir() {
  local src="$1" dest="$2"
  [[ -d "$src" ]] || { log "skip missing $src"; return 0; }
  if [[ -L "$src" ]]; then
    local target
    target="$(readlink "$src")"
    if [[ "$target" == "$dest" ]]; then
      log "ok already linked $src"
      return 0
    fi
  fi
  log "import dir $src -> $dest"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  rm -rf "$dest"
  cp -a "$src" "$dest"
}

# settings: sanitize
if [[ -f "$PI_AGENT_DIR/settings.json" ]]; then
  if [[ -L "$PI_AGENT_DIR/settings.json" ]] && \
     [[ "$(readlink "$PI_AGENT_DIR/settings.json")" == "$REPO_DIR/agent/settings.json" ]]; then
    log "ok settings already linked"
  else
    log "import+sanitize settings.json"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      python3 - <<PY
import json
from pathlib import Path
src = Path("$PI_AGENT_DIR/settings.json")
dst = Path("$REPO_DIR/agent/settings.json")
# If symlink to elsewhere, read resolved content
data = json.loads(src.read_text())
data.pop("lastChangelogVersion", None)
data.pop("trackingId", None)
dst.write_text(json.dumps(data, indent=2) + "\n")
PY
    fi
  fi
fi

copy_file "$PI_AGENT_DIR/models.json" "$REPO_DIR/agent/models.json"
copy_file "$PI_AGENT_DIR/keybindings.json" "$REPO_DIR/agent/keybindings.json"
copy_file "$PI_AGENT_DIR/mcp.json" "$REPO_DIR/agent/mcp.json"

# extensions (files only at top level + optional subagent config)
if [[ -d "$PI_AGENT_DIR/extensions" ]]; then
  mkdir -p "$REPO_DIR/agent/extensions"
  shopt -s nullglob
  for f in "$PI_AGENT_DIR/extensions"/*; do
    base="$(basename "$f")"
    if [[ -f "$f" || -L "$f" ]]; then
      # resolve content into repo file
      if [[ -L "$f" && "$(readlink "$f")" == "$REPO_DIR/agent/extensions/$base" ]]; then
        log "ok ext $base"
      else
        copy_file "$f" "$REPO_DIR/agent/extensions/$base"
      fi
    fi
  done
  shopt -u nullglob
  if [[ -f "$PI_AGENT_DIR/extensions/subagent/config.json" ]]; then
    copy_file \
      "$PI_AGENT_DIR/extensions/subagent/config.json" \
      "$REPO_DIR/agent/extensions/subagent/config.json"
  fi
fi

# skills that already exist in repo, or all under agents skills if named
if [[ -d "$AGENTS_SKILLS_DIR" ]]; then
  shopt -s nullglob
  for d in "$AGENTS_SKILLS_DIR"/*; do
    [[ -d "$d" || -L "$d" ]] || continue
    name="$(basename "$d")"
    dest="$REPO_DIR/agents-skills/$name"
    if [[ -L "$d" && "$(readlink "$d")" == "$dest" ]]; then
      log "ok skill $name"
      continue
    fi
    # Only import if already managed or user created under skills dir
    if [[ -d "$dest" || ! -e "$dest" ]]; then
      copy_dir "$d" "$dest"
    fi
  done
  shopt -u nullglob
fi

log "done — review with: git -C $REPO_DIR status && git -C $REPO_DIR diff"
log "never commit auth.json or sessions"
