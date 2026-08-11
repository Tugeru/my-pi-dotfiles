# Model Relay — Reference

Disclosed reference for [SKILL.md](SKILL.md). Loaded on demand during takeover reconstruction.

## Artifact Checklist

Read the strongest available artifacts relevant to the active objective. Skip what doesn't exist.

### Domain and planning

- `CONTEXT.md`
- `AGENTS.md`
- Relevant README or project documentation
- ADRs in the area being touched
- Planning maps, investigation findings, or design documents
- Approved specification
- Ticket breakdown

### Work tracking

Resolve when available via GitHub tooling:

- Active GitHub Issue
- Parent or epic issue
- Child issues
- Blocking and blocked-by issues
- Related pull request
- Follow-up or deferred issues
- Issue acceptance criteria and recent material comments

Preserve known references. Mark unavailable relationships `UNKNOWN`.

### Existing handoff

When a handoff document was created, read it — but verify its claims against current issues, files, git state, and validation results. A handoff is evidence, not execution truth.

## Vertical Slice Reconstruction

Describe the active slice through its observable outcome:

- User-visible or system-visible outcome
- Included architectural layers
- Acceptance criteria
- Validation seam
- Explicit non-goals
- Work assigned to other issues

Relevant layers:

```
UI · API/server action · application logic · domain logic
authorization · persistence · validation · tests
observability · documentation
```

Detect incomplete cross-layer work:

- Schema without migration
- Endpoint without authorization
- UI without backend support
- Changed types with outdated callers
- Implementation without required validation

Stay within the active slice unless a verified blocker requires work elsewhere.

## File Accounting Categories

Account for every changed, staged, or untracked file:

| Category | Meaning |
|----------|---------|
| Active-issue work | Directly serves the current issue |
| Supporting slice work | Enables the slice but not the issue alone |
| Unrelated pre-existing | Was changed before the takeover, unrelated |
| Generated artifact | Build output, types, lockfile |
| `UNKNOWN` | Insufficient evidence to classify |

## Task Ledger Notation

```
[x] DONE         — verified artifact, code, commit, or passing validation
[~] IN PROGRESS  — started but incomplete or partially integrated
[ ] TODO         — required but not started
[!] BLOCKED      — waiting on dependency, decision, or environment
[-] DEFERRED     — intentionally outside the active slice (preferably in another issue)
[?] UNKNOWN      — insufficient evidence
```

A modified file proves activity, not completion. When issue checkboxes, comments, commits, current changes, and test results disagree on a criterion's state, report the disagreement with sources rather than choosing silently.

## Skill Selection

Choose the continuation skill from those available to you. Review the installed skills and match one to the active objective.

**Selection process:**

1. Identify the objective type — investigation, planning, implementation, debugging, review, or handoff.
2. Scan available skills for the one whose description matches that objective type.
3. If the previous model was mid-skill, continue that same skill from its first incomplete task.
4. If the previous skill's completion condition was met, select the next skill in the workflow's natural progression.
5. If no installed skill fits, continue the work directly without invoking a skill.

When in doubt, ask the user which skill was active — they often know immediately.

Continue the same skill when its objective is unfinished. Move to the next only when the previous skill's completion condition is verified.

## Takeover Declaration Template

Emit before acting in step 5:

```
MODEL RELAY TAKEOVER

Previous skill:
Current phase:
Active issue:
Active vertical slice:
Interruption point:
Repository verified:
Next skill:
Next concrete action:
```

## Context Compaction

If context pressure independently requires compaction during a takeover:

1. Finish the task ledger (step 4).
2. Persist durable decisions to issue comments or files.
3. Record repository state (branch, HEAD, diff summary).
4. Record validation state (last test/build results).
5. Run compaction.
6. Repeat Model Relay reconstruction from step 2 using the compacted context before continuing.

Do not compact merely because the provider changed — only when the context window is genuinely under pressure.
