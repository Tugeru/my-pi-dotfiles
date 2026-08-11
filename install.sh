#!/usr/bin/env bash
# Install pi dotfiles: settings, models, extensions, skills, packages.
# Safe defaults: never overwrites auth.json, sessions, or package caches.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="symlink"              # symlink | copy
PROFILE="full"              # full | minimal | orca
DRY_RUN=0
SKIP_PACKAGES=0
SKIP_SKILLS=0
WITH_ORCA=1
ORCA_SET=0                  # 1 if user passed --with-orca/--no-orca
INSTALL_EXTENSIONS=1
INSTALL_PI=0
DOCTOR_ONLY=0
FORCE=0

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
AGENTS_SKILLS_DIR="${PI_AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"

CORE_SKILLS=(
  caveman
  ponytail
  humanizer
  git-commit
  shadcn
  design-taste-frontend
  emil-design-eng
  find-skills
  teach
  writing-great-skills
  model-relay
)
ORCA_SKILLS=(computer-use orca-cli orchestration)
ORCA_EXTENSIONS=(orca-agent-status.ts orca-prefill.ts orca-titlebar-spinner.ts)

# Packages come from agent/settings.json; fallback list if jq/python missing
DEFAULT_PACKAGES=(
  "npm:pi-subagents@0.46.0"
  "npm:pi-web-access@0.21.0"
  "git:github.com/kotarac/pi-fetch@v2.0.0"
)

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
run()  {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'dry-run: %s\n' "$*"
  else
    "$@"
  fi
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --mode symlink|copy   Install method (default: symlink)
  --profile NAME        full | minimal | orca (default: full)
  --with-orca           Include Orca extensions/skills (default on for full/orca)
  --no-orca             Skip Orca extensions/skills
  --skip-packages       Do not run pi install
  --skip-skills         Do not install skills
  --pi-install          Install/update the pi CLI via npm if missing
  --force               Replace managed targets even if they exist as regular files
  --dry-run             Print actions without changing the system
  --doctor              Only verify the current install
  -h, --help            Show this help

Environment:
  PI_CODING_AGENT_DIR   Override pi config dir (default: ~/.pi/agent)
  PI_AGENTS_SKILLS_DIR  Override skills dir (default: ~/.agents/skills)
EOF
}

load_profile() {
  local file="$REPO_DIR/profiles/${PROFILE}.env"
  local profile_orca=""
  if [[ -f "$file" ]]; then
    # shellcheck disable=SC1090
    source "$file"
    # Capture profile WITH_ORCA before deciding; explicit CLI flags win.
    profile_orca="${WITH_ORCA:-}"
    if [[ "$ORCA_SET" -eq 0 && -n "$profile_orca" ]]; then
      WITH_ORCA="$profile_orca"
    fi
    if [[ "${INSTALL_SKILLS:-1}" == "0" ]]; then SKIP_SKILLS=1; fi
    if [[ "${INSTALL_PACKAGES:-1}" == "0" ]]; then SKIP_PACKAGES=1; fi
    if [[ "${INSTALL_EXTENSIONS:-1}" == "0" ]]; then INSTALL_EXTENSIONS=0; fi
  else
    warn "unknown profile '$PROFILE' (continuing with flags)"
  fi
}

timestamp() { date +%Y%m%d%H%M%S; }

backup_if_needed() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" ]]; then
      return 0
    fi
    local bak
    bak="${target}.bak.$(timestamp)"
    log "backup $target -> $bak"
    run mv "$target" "$bak"
  fi
}

# Link or copy src -> dest. If dest is already correct symlink, skip.
install_path() {
  local src="$1"
  local dest="$2"
  local dest_dir
  dest_dir="$(dirname "$dest")"

  [[ -e "$src" || -L "$src" ]] || die "missing source: $src"
  run mkdir -p "$dest_dir"

  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" == "$src" && "$FORCE" -eq 0 ]]; then
      log "ok symlink $dest"
      return 0
    fi
    log "replace symlink $dest"
    run rm "$dest"
  elif [[ -e "$dest" ]]; then
    if [[ "$FORCE" -eq 0 && "$MODE" == "copy" && -f "$src" && -f "$dest" ]] && cmp -s "$src" "$dest"; then
      log "ok file $dest (identical)"
      return 0
    fi
    # Symlink mode always replaces regular files/dirs so live path tracks the repo.
    backup_if_needed "$dest"
  fi

  if [[ "$MODE" == "symlink" ]]; then
    log "symlink $dest -> $src"
    run ln -s "$src" "$dest"
  else
    if [[ -d "$src" ]]; then
      log "copy dir $src -> $dest"
      run cp -a "$src" "$dest"
    else
      log "copy $src -> $dest"
      run cp -a "$src" "$dest"
    fi
  fi
}

ensure_pi() {
  if command -v pi >/dev/null 2>&1; then
    log "pi found: $(command -v pi)"
    return 0
  fi
  if [[ "$INSTALL_PI" -eq 1 ]]; then
    command -v npm >/dev/null 2>&1 || die "npm required to install pi"
    log "installing pi CLI via npm"
    run npm install -g --ignore-scripts @earendil-works/pi-coding-agent
    command -v pi >/dev/null 2>&1 || die "pi installed but not on PATH"
  else
    die "pi not found on PATH. Install it, or re-run with --pi-install"
  fi
}

read_packages() {
  local settings="$REPO_DIR/agent/settings.json"
  if [[ -f "$settings" ]] && command -v python3 >/dev/null 2>&1; then
    python3 - <<PY
import json
from pathlib import Path
data = json.loads(Path("$settings").read_text())
for p in data.get("packages", []):
    if isinstance(p, str):
        print(p)
    elif isinstance(p, dict) and "source" in p:
        print(p["source"])
PY
    return
  fi
  printf '%s\n' "${DEFAULT_PACKAGES[@]}"
}

install_packages() {
  [[ "$SKIP_PACKAGES" -eq 1 ]] && { log "skip packages"; return 0; }
  ensure_pi
  local pkg
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    log "pi install $pkg"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'dry-run: pi install %s\n' "$pkg"
    else
      # pi install is idempotent enough; ignore already-present noise
      if ! pi install "$pkg"; then
        warn "pi install failed for $pkg (continuing)"
      fi
    fi
  done < <(read_packages)
}

install_agent_files() {
  run mkdir -p "$PI_AGENT_DIR"/{extensions,skills,prompts,themes}

  install_path "$REPO_DIR/agent/settings.json" "$PI_AGENT_DIR/settings.json"
  install_path "$REPO_DIR/agent/models.json" "$PI_AGENT_DIR/models.json"

  if [[ "$INSTALL_EXTENSIONS" -eq 0 ]]; then
    log "skip extensions (profile)"
    return 0
  fi

  local ext
  shopt -s nullglob
  for ext in "$REPO_DIR/agent/extensions"/*; do
    local base
    base="$(basename "$ext")"
    # Skip Orca extensions when disabled
    if [[ "$WITH_ORCA" -eq 0 ]]; then
      local skip=0
      local o
      for o in "${ORCA_EXTENSIONS[@]}"; do
        [[ "$base" == "$o" ]] && skip=1 && break
      done
      [[ "$skip" -eq 1 ]] && { log "skip orca ext $base"; continue; }
    fi
    install_path "$ext" "$PI_AGENT_DIR/extensions/$base"
  done
  shopt -u nullglob

  # Optional subagent config if present in repo
  if [[ -f "$REPO_DIR/agent/extensions/subagent/config.json" ]]; then
    run mkdir -p "$PI_AGENT_DIR/extensions/subagent"
    install_path \
      "$REPO_DIR/agent/extensions/subagent/config.json" \
      "$PI_AGENT_DIR/extensions/subagent/config.json"
  fi
}

install_skills() {
  [[ "$SKIP_SKILLS" -eq 1 ]] && { log "skip skills"; return 0; }
  run mkdir -p "$AGENTS_SKILLS_DIR"

  local skills=("${CORE_SKILLS[@]}")
  if [[ "$WITH_ORCA" -eq 1 ]]; then
    skills+=("${ORCA_SKILLS[@]}")
  fi

  local name
  for name in "${skills[@]}"; do
    local src="$REPO_DIR/agents-skills/$name"
    if [[ ! -d "$src" ]]; then
      warn "skill not in repo: $name"
      continue
    fi
    install_path "$src" "$AGENTS_SKILLS_DIR/$name"
  done
}

print_auth_help() {
  cat <<EOF

Auth (local only — never committed):
  Config dir: $PI_AGENT_DIR/auth.json
  Example:    $REPO_DIR/auth/auth.json.example

  After install, in pi:
    /login          # OAuth providers (e.g. OpenAI Codex)
  Or set API keys via /login or environment variables for kie/opencode.

EOF
}

doctor() {
  local ok=1
  log "doctor: PI_AGENT_DIR=$PI_AGENT_DIR"
  log "doctor: AGENTS_SKILLS_DIR=$AGENTS_SKILLS_DIR"
  log "doctor: REPO_DIR=$REPO_DIR"

  check_link() {
    local dest="$1"
    local src="$2"
    if [[ -L "$dest" ]]; then
      local cur
      cur="$(readlink "$dest")"
      if [[ "$cur" == "$src" ]]; then
        printf '  OK  symlink %s\n' "$dest"
      else
        printf '  BAD symlink %s -> %s (expected %s)\n' "$dest" "$cur" "$src"
        ok=0
      fi
    elif [[ -e "$dest" ]]; then
      if [[ "$MODE" == "copy" ]] || [[ ! -d "$src" ]]; then
        if [[ -f "$dest" && -f "$src" ]] && cmp -s "$dest" "$src"; then
          printf '  OK  file %s (matches repo)\n' "$dest"
        else
          printf '  WARN present %s (not symlink to repo)\n' "$dest"
        fi
      else
        printf '  WARN present %s (not symlink to repo)\n' "$dest"
      fi
    else
      printf '  MISSING %s\n' "$dest"
      ok=0
    fi
  }

  check_link "$PI_AGENT_DIR/settings.json" "$REPO_DIR/agent/settings.json"
  check_link "$PI_AGENT_DIR/models.json" "$REPO_DIR/agent/models.json"

  local ext
  shopt -s nullglob
  for ext in "$REPO_DIR/agent/extensions"/*; do
    [[ -f "$ext" ]] || continue
    check_link "$PI_AGENT_DIR/extensions/$(basename "$ext")" "$ext"
  done
  shopt -u nullglob

  local name
  for name in "${CORE_SKILLS[@]}"; do
    [[ -d "$REPO_DIR/agents-skills/$name" ]] || continue
    check_link "$AGENTS_SKILLS_DIR/$name" "$REPO_DIR/agents-skills/$name"
  done

  if [[ -f "$PI_AGENT_DIR/auth.json" ]]; then
    printf '  OK  auth.json present (local)\n'
  else
    printf '  WARN auth.json missing — run /login or copy from auth/auth.json.example\n'
  fi

  if command -v pi >/dev/null 2>&1; then
    printf '  OK  pi on PATH\n'
    if [[ "$DRY_RUN" -eq 0 ]]; then
      log "pi list"
      pi list || true
    fi
  else
    # Missing pi is a setup hint, not a broken dotfiles install (CI smoke skips packages).
    printf '  WARN pi not on PATH (install with ./install.sh --pi-install or npm i -g @earendil-works/pi-coding-agent)\n'
  fi

  [[ "$ok" -eq 1 ]] || return 1
  log "doctor: all good"
}

# --- args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --with-orca) WITH_ORCA=1; ORCA_SET=1; shift ;;
    --no-orca) WITH_ORCA=0; ORCA_SET=1; shift ;;
    --skip-packages) SKIP_PACKAGES=1; shift ;;
    --skip-skills) SKIP_SKILLS=1; shift ;;
    --pi-install) INSTALL_PI=1; shift ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --doctor) DOCTOR_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ "$MODE" == "symlink" || "$MODE" == "copy" ]] || die "--mode must be symlink or copy"

load_profile

if [[ "$DOCTOR_ONLY" -eq 1 ]]; then
  doctor
  exit $?
fi

log "repo:     $REPO_DIR"
log "pi agent: $PI_AGENT_DIR"
log "skills:   $AGENTS_SKILLS_DIR"
log "mode:     $MODE"
log "profile:  $PROFILE"
log "orca:     $WITH_ORCA"

install_agent_files
install_skills
install_packages
print_auth_help

if [[ "$DRY_RUN" -eq 0 ]]; then
  doctor || warn "doctor reported issues"
fi

log "done"
