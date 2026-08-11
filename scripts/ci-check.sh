#!/usr/bin/env bash
# Static structure checks for my-pi-dotfiles (run locally or in CI).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

failures=0
pass() { printf '  OK  %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*" >&2; failures=$((failures + 1)); }
warn() { printf '  WARN %s\n' "$*" >&2; }

echo "==> ci-check: $REPO_DIR"

# --- required paths ---
required_paths=(
  install.sh
  agent/settings.json
  agent/models.json
  auth/auth.json.example
  profiles/full.env
  profiles/minimal.env
  profiles/orca.env
  scripts/doctor.sh
  scripts/sync-from-live.sh
  .gitignore
)
for p in "${required_paths[@]}"; do
  if [[ -e "$p" ]]; then
    pass "exists $p"
  else
    fail "missing $p"
  fi
done

# --- JSON validity ---
json_files=(
  agent/settings.json
  agent/models.json
  auth/auth.json.example
)
while IFS= read -r -d '' f; do
  json_files+=("$f")
done < <(find agents-skills -type f -name '*.json' -print0 2>/dev/null || true)

for f in "${json_files[@]}"; do
  if python3 -m json.tool "$f" >/dev/null 2>&1; then
    pass "json $f"
  else
    fail "invalid json $f"
  fi
done

# --- settings shape + package pins ---
python3 - <<'PY' || failures=$((failures + 1))
import json, re, sys
from pathlib import Path

settings = json.loads(Path("agent/settings.json").read_text())
models = json.loads(Path("agent/models.json").read_text())
example = json.loads(Path("auth/auth.json.example").read_text())

ok = True
def fail(msg):
    global ok
    ok = False
    print(f"  FAIL {msg}", file=sys.stderr)

def passed(msg):
    print(f"  OK  {msg}")

for key in ("packages",):
    if key not in settings:
        fail(f"settings.json missing '{key}'")
    else:
        passed(f"settings has {key}")

for key in ("defaultProvider", "defaultModel", "theme"):
    if key in settings:
        passed(f"settings has {key}={settings[key]!r}")
    else:
        fail(f"settings.json missing recommended key '{key}'")

# ban machine-only keys
for banned in ("lastChangelogVersion", "trackingId"):
    if banned in settings:
        fail(f"settings.json should not commit '{banned}'")

packages = settings.get("packages") or []
if not isinstance(packages, list) or not packages:
    fail("settings.packages must be a non-empty list")
else:
    passed(f"{len(packages)} package entries")

npm_pin = re.compile(r"^npm:(@?[^@/]+(?:/[^@]+)?)@[^@]+$")
# git:host/path@ref  or git:git@host:path@ref — require a ref after final @
git_pin = re.compile(r"^git:.+@[^@/]+$")

for p in packages:
    if isinstance(p, dict):
        src = p.get("source", "")
    else:
        src = str(p)
    if src.startswith("npm:"):
        if npm_pin.match(src):
            passed(f"pinned npm {src}")
        else:
            fail(f"unpinned or malformed npm package: {src} (want npm:name@version)")
    elif src.startswith("git:"):
        # must have @ref and not end with just host/path
        if "@" in src[4:] and git_pin.match(src):
            passed(f"pinned git {src}")
        else:
            fail(f"unpinned or malformed git package: {src} (want git:host/path@ref)")
    elif src.startswith("/") or src.startswith("."):
        passed(f"local package path {src}")
    else:
        fail(f"unknown package source form: {src}")

if "providers" not in models or not models["providers"]:
    fail("models.json missing providers")
else:
    passed(f"models providers: {', '.join(models['providers'])}")

# auth example must not look like real secrets
secretish = re.compile(r"^(sk-|gho_|ghp_|xai-|AKIA)[A-Za-z0-9_\-]{8,}$")
def walk(obj, path="$"):
    if isinstance(obj, dict):
        for k, v in obj.items():
            walk(v, f"{path}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            walk(v, f"{path}[{i}]")
    elif isinstance(obj, str):
        if secretish.match(obj):
            fail(f"auth example looks like a real secret at {path}")
        if obj not in ("REPLACE_ME",) and len(obj) > 20 and " " not in obj:
            if path.endswith(".key") or path.endswith(".access") or path.endswith(".refresh"):
                fail(f"auth example has non-placeholder credential at {path}")

walk(example)
passed("auth.json.example has no obvious real secrets")

# models.json should not embed api keys
raw = Path("agent/models.json").read_text()
if re.search(r'"apiKey"\s*:\s*"(?!ollama|\$)[^"]{8,}"', raw):
    fail("models.json appears to embed a real apiKey")
else:
    passed("models.json has no embedded apiKey secrets")

sys.exit(0 if ok else 1)
PY

# --- extensions ---
shopt -s nullglob
exts=(agent/extensions/*.ts agent/extensions/*.js)
shopt -u nullglob
if [[ ${#exts[@]} -eq 0 ]]; then
  fail "no extensions under agent/extensions/"
else
  for ext in "${exts[@]}"; do
    if [[ -s "$ext" ]]; then
      pass "extension $ext"
    else
      fail "empty extension $ext"
    fi
  done
fi

# --- skills: every agents-skills/* has SKILL.md ---
shopt -s nullglob
skill_dirs=(agents-skills/*/)
shopt -u nullglob
if [[ ${#skill_dirs[@]} -eq 0 ]]; then
  fail "no skills under agents-skills/"
fi
for d in "${skill_dirs[@]}"; do
  name="$(basename "$d")"
  if [[ -f "${d}SKILL.md" ]]; then
    # basic frontmatter
    if grep -q '^description:' "${d}SKILL.md" || grep -q '^description: |' "${d}SKILL.md" || grep -q '^description: >' "${d}SKILL.md"; then
      pass "skill $name"
    else
      # name-only still loads poorly in pi; require description
      if grep -qE '^---$' "${d}SKILL.md"; then
        if grep -qE '^description:' "${d}SKILL.md"; then
          pass "skill $name"
        else
          fail "skill $name SKILL.md missing description frontmatter"
        fi
      else
        fail "skill $name SKILL.md missing frontmatter"
      fi
    fi
  else
    fail "skill $name missing SKILL.md"
  fi
done

# --- install.sh skill lists must exist on disk ---
# Parse simple array assignments from install.sh
mapfile -t install_skills < <(python3 - <<'PY'
import re
from pathlib import Path
text = Path("install.sh").read_text()
for arr in ("CORE_SKILLS", "ORCA_SKILLS"):
    m = re.search(rf"{arr}=\((.*?)\)", text, re.S)
    if not m:
        print(f"MISSING_ARRAY:{arr}", flush=True)
        continue
    body = m.group(1)
    for name in re.findall(r"([A-Za-z0-9_-]+)", body):
        print(name)
PY
)
for name in "${install_skills[@]}"; do
  if [[ "$name" == MISSING_ARRAY:* ]]; then
    fail "install.sh missing ${name#MISSING_ARRAY:}"
    continue
  fi
  if [[ -f "agents-skills/$name/SKILL.md" ]]; then
    pass "install.sh skill present $name"
  else
    fail "install.sh references missing skill $name"
  fi
done

# --- forbidden tracked paths (if present in worktree as tracked intent) ---
forbidden=(
  auth/auth.json
  agent/auth.json
  agent/sessions
  agent/missions
  agent/npm
  agent/git
  agent/models-store.json
  agent/trust.json
  agent/run-history.jsonl
)
for p in "${forbidden[@]}"; do
  if [[ -e "$p" ]]; then
    fail "forbidden path present in repo worktree: $p"
  else
    pass "absent forbidden $p"
  fi
done

# --- .gitignore covers secrets ---
for pattern in auth/auth.json models-store.json; do
  if grep -qF "$pattern" .gitignore || grep -q 'auth\.json' .gitignore; then
    pass "gitignore mentions secrets pattern ($pattern)"
  else
    warn "gitignore may not mention $pattern"
  fi
done

# --- scripts executable ---
for s in install.sh scripts/ci-check.sh scripts/doctor.sh scripts/sync-from-live.sh; do
  if [[ -x "$s" ]]; then
    pass "executable $s"
  else
    fail "not executable $s"
  fi
done

echo
if [[ "$failures" -gt 0 ]]; then
  echo "ci-check: $failures failure(s)" >&2
  exit 1
fi
echo "ci-check: all good"
