---
name: model-relay
description: Resume active work after switching models or providers.
disable-model-invocation: true
---

# Model Relay

**Takeover** — assume command of active work after a model or provider switch. Reconstruct the previous agent's state from artifacts and repository, not from its hidden reasoning. Resume through the correct skill once the takeover is safe.

## 1. Establish the Takeover

Confirm from conversation: quota exhausted, rate-limited, provider failure, interrupted response, or deliberate switch during active work.

Determine whether the previous model stopped between tasks, mid-edit, mid-command, or after completing a phase. Treat interrupted operations as incomplete until verified.

**Complete when:** reason for takeover and interruption point are identified or marked `UNKNOWN`.

## 2. Reconstruct the Objective

Build the hierarchy:

```
Project objective → workflow phase → active skill → GitHub Issue → vertical slice → immediate action
```

Identify the skill or workflow currently being executed and whether its completion condition was reached.

**Complete when:** active objective, phase, skill, issue, slice, and immediate action are resolved or `UNKNOWN`.

## 3. Load Context and Verify State

Read authoritative artifacts for the active objective — see [REFERENCE.md](REFERENCE.md) for the full artifact checklist.

Run git inspection:

```bash
git status --short
git branch --show-current
git rev-parse --short HEAD
git diff --stat
git diff --cached --stat
git log --oneline -5
```

Keep git **read-only** during reconstruction. Preserve staged, unstaged, and untracked work.

Account for every changed file as: active-issue work, supporting slice work, unrelated pre-existing work, generated artifact, or `UNKNOWN`.

For interrupted commands, edits, or tests: determine what completed, preserve valid partial work, run the narrowest safe validation to resolve uncertainty.

**Complete when:** every artifact read or identified as unavailable, every changed file accounted for, interrupted operations verified.

## 4. Build Task Ledger

Classify every acceptance criterion and material task — see [REFERENCE.md](REFERENCE.md) for notation and evidence requirements.

A modified file proves activity, not completion. Reconcile disagreements among issue checkboxes, comments, commits, current changes, and test results — report the disagreement instead of choosing silently.

**Complete when:** every active criterion has exactly one state with evidence.

## 5. Select Skill and Resume

Pick the continuation skill by reviewing the available skills and matching one to the active objective. Continue the same skill when its objective is unfinished. Move to the next only when the previous skill's completion condition is verified. See [REFERENCE.md](REFERENCE.md) for selection guidance.

Before acting, emit a **takeover declaration** — see [REFERENCE.md](REFERENCE.md) for the template.

Then invoke the selected skill and continue from the first incomplete task.

**Complete when:** the next concrete action has started through the correct skill.

## Takeover Completion Gate

Do not claim a successful takeover until:

- [ ] Previous objective identified
- [ ] Active issue and slice identified or `UNKNOWN`
- [ ] Authoritative artifacts read
- [ ] Every changed file accounted for (when repository work exists)
- [ ] Every acceptance criterion has a task state
- [ ] Interrupted operations verified
- [ ] Continuation skill selected from available skills
- [ ] Continuation started

## Guardrails

- Keep credentials, tokens, and secrets out of all output.
- Git is **read-only** during steps 1–4. Destructive git operations require separate user approval.
- Keep the active GitHub Issue as the scope boundary — do not expand beyond the active slice.
