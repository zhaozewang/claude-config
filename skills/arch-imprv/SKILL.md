---
name: arch-imprv
description: "End-to-end SOP that closes the architectural drift loop: /architect-review → triage findings with the user → /architect-plan the approved ones → /ship each phase in order → /architect-review --full to confirm zero regressions. Uses existing skills (/architect-review, /architect-plan, /ship) under the hood — adds no new executor. Takes an optional --scope; without one, runs a quick global review and asks the user which child scope to drill into."
argument-hint: "[--scope <path>]"
user-invocable: true
context: fork
---

# arch-imprv — closed-loop architectural improvement SOP

## ON INVOCATION — START IMMEDIATELY

**The `/arch-imprv` invocation IS the task.** Do not ask the user what to do. Do not wait for a follow-up message. Do not treat this SKILL.md as "context to acknowledge" — it is a procedure to **execute**.

Dispatch rules:
- **`/arch-imprv`** (no args) → go directly to **Stage A** and invoke `/architect-review` at the repo root (global scope). When Stage A finishes, THEN ask the user to pick a child scope from the ranked list. The scope question belongs inside Stage A, not before it.
- **`/arch-imprv --scope <path>`** → go directly to **Stage A** and invoke `/architect-review --scope <path>`. Skip the scope question.
- **Any other free-text arg** → treat as an implied scope if it's a valid path; otherwise error and show the two valid forms above.

User checkpoints exist **only** at the points explicitly marked in Stages B and C. Anywhere else, proceed without asking.

If you find yourself typing "Could you share what you'd like me to do?" after this skill fires — stop. The answer is in Stage A below. Go do it.

---

Five stages. Checkpoint with the user between stages B→C and C→D. Auto-proceed within stage D; halt on any `/ship` failure. Stage E is mandatory and ship-blocking.

```
A. REVIEW     →  /architect-review
B. TRIAGE     →  user approval (MUST-DOs are non-deferrable)
C. PLAN       →  /architect-plan --from-review
D. SHIP       →  /ship <phase-slug> per phase, in order
E. VERIFY     →  /architect-review --full (zero-regression gate)
```

This skill adds **zero new executor logic**. It is the glue that turns "something might be drifting" into "cycle complete, zero regressions" without the user having to remember the order, the `--from-review` wiring, or the final verification.

## Invocation

```
/arch-imprv                                    # quick global review → ask user for scope → continue
/arch-imprv --scope src/bpx_hub/scheduler      # skip the ask; review+fix that scope
```

## When to use

- A `/architect-review` on some scope flagged drift and you're ready to act on it.
- A feature-regression finding was raised — zero-tolerance means this is the intended path to clear it.
- End-of-phase hygiene after shipping a batch of features.

## When NOT to use

- Pure per-PR cleanup inside a single feature's scope → use the code-review plugin.
- Forward work (new feature) → use `/architect-plan` directly, not this skill.
- ADR work (undocumented-intent / undocumented-convention findings) → this skill cannot fix those; it will surface them and point you at `docs/adr/`.

---

## Stage A — REVIEW

1. **If `--scope` given:** invoke `/architect-review --scope <path>`.
2. **If no `--scope`:**
   - Invoke `/architect-review` (global). This produces the quick overview — at global scope the critic assesses cross-cutting layering, not per-module depth, so it is already the fast pass.
   - Parse the navigation header of the resulting report. Extract the ranked child list.
   - Print to the user:
     ```
     Global review complete. Ranked subsystems by drift pressure:
       0.79  src/bpx_hub/scheduler
       0.62  src/bpx_hub/remote
       0.45  src/bpx_hub/api
       ...
     Pick a scope to drill into, or type "global" to act on repo-wide findings.
     ```
   - On user input, invoke `/architect-review --scope <chosen-path>`.
3. Parse the resulting review file (both full and delta formats supported — they share the same `state.json`). Extract:
   - Executive summary
   - `findings[]` grouped by `kind` and `effort`
   - `feature_regressions` (from `feature_reconciliation.regressed`)

**Early exit:** if `findings = []` and `feature_regressions = []`, print `No drift or regressions at <scope>. Nothing to fix.` and exit cleanly.

---

## Stage B — TRIAGE (user approval)

Classify the findings:

| Class | Source | Deferrable? |
|---|---|---|
| **MUST-DO** | every `feature-regression` | No |
| **one-pr** | `effort: one-pr` | Yes |
| **multi-pr** | `effort: multi-pr` | Yes |
| **phased-refactor** | `effort: phased-refactor` | Yes |
| **ADR-required** | `undocumented-intent`, `undocumented-convention`, `stale-rule` | Yes — excluded from this cycle; needs ADR work first |

Present to the user:

```
Findings at <scope>:

  [MUST-DO — 1]
    F-REG-001  feat-route-post-v1-acquire — anchors vanished since e3c8a62
               (pre-selected, not deferrable)

  [phased-refactor — 2]
    [ ] F-003   scheduler/routing.py has circular import with session_affinity.py
    [ ] F-007   unbounded retry queue in remote/dashscope.py

  [one-pr — 1]
    [ ] F-012   duplicate middleware registration in main.py

  [ADR-required — 1 — cannot fix in this cycle]
    F-021       undocumented convention: every route wraps db calls in with_transaction()
                → draft docs/adr/NNNN-with-transaction.md, then re-run /architect-review
```

Ask: `Which non-MUST-DO findings do you want to include in this cycle? (comma-separated IDs, "all", or "none")`

Compute the work item:
- `approved_findings` = MUST-DOs ∪ user-selected IDs
- Goal sentence: `"address <N> findings in scope <path>: <id-list>"`
- `needs_planning = any(f.effort == "phased-refactor" for f in approved_findings)`

Routing:
- `needs_planning == True` → proceed to Stage C.
- `needs_planning == False` and `len(approved_findings) >= 1` → skip to Stage D with a **direct `/ship`** (no phase-skills needed for one-pr / multi-pr only).
- `len(approved_findings) == 0` → print "nothing approved; exiting" and exit.

---

## Stage C — PLAN (user approval)

Invoke `/architect-plan --from-review <state.json-path> "<goal-sentence>"`.

`/architect-plan` will:
- Read `feature_inventory` from the state.json — the zero-tolerance preservation gate.
- Write phase-skills under `.claude/skills/<phase-slug>/` (internal checkpoints per its own workflow).
- Return an ordered list of `/ship <phase-slug>` commands.

When `/architect-plan` returns, surface the summary to the user:

```
Plan written: .claude/plans/<slug>-<date>.md
Phases (<N>):
  1. /ship <phase-1-slug>
  2. /ship <phase-2-slug>
  ...

Approve to start shipping these in order? [y/N]
```

- User approves → Stage D.
- User declines → exit. Phase-skills remain on disk so the user can resume manually later (`/ship <phase-slug>`) or re-invoke `/arch-imprv` (resumption path below).

---

## Stage D — SHIP (per-phase)

### Case 1: one-pr / multi-pr only (no planning)
Single invocation:
```
/ship "<goal-sentence>" — context: findings <id-list> from docs/architecture-reviews/<slug>/<review-file>
```
`/ship` routes to the manager agent, which runs its own closed-loop pipeline.

### Case 2: phased plan
For each `phase-slug` in the ordered list:
1. Invoke `/ship <phase-slug>`.
2. Wait for completion.
3. On **PASS** → print one-line confirmation `phase <N>/<total> [<slug>] — shipped`. Continue.
4. On **FAIL** → **HALT Stage D** with an explicit **test-failure classification** so the user knows whether to fix code or update tests:
   - Read the phase-skill's `## Test Impact` section.
   - For each failing test reported by the manager, classify as one of:
     - **INTENDED** — test is listed under `Test Impact → Expected to change`. The phase was supposed to update it but didn't, or the update was incomplete. Fix: update the test inside this phase's approved scope.
     - **UNINTENDED (preserved feature regression)** — test is listed under `Test Impact → Must stay green`. The phase broke behavior it promised to preserve. Fix: the code, not the test. Do NOT "update" this test to make it pass — doing so is a silent feature regression.
     - **UNINTENDED (out-of-scope)** — test is not in Test Impact at all. The phase touched code outside its declared `Touches`. Fix: revert the offending change and re-scope the phase.
     - **UNCLASSIFIABLE** — the phase-skill is missing or malformed Test Impact. Fix: the plan is broken; abort the cycle and re-run `/architect-plan`.
   - Print the classification per failing test. Example:
     ```
     phase 2/4 [scheduler-decouple-routing] — FAILED

     Failing tests, classified:
       tests/unit/test_routing.py::test_bin_pack
         INTENDED — listed under Expected to change (anchor moved to scheduler/placement.py)
         → update the test within this phase's scope

       tests/e2e/test_happy_path.py
         UNINTENDED (preserved feature regression)
         → covers feat-route-post-v1-acquire which this phase promised to preserve
         → fix the code, not the test

       tests/integration/test_affinity_cache.py
         UNINTENDED (out-of-scope)
         → this test is not in Test Impact; the phase touched code outside its Touches
         → revert the out-of-scope change
     ```
   - Save resumption state (which phase failed, which earlier phases succeeded).
   - Exit non-zero. User addresses the blocker. Re-invocation of `/arch-imprv` detects in-progress work and offers to resume from the failed phase (not from the start).

### Safety warnings
- If `>3` phased-refactor findings are approved in one cycle, WARN before entering Stage D: *"3+ structural phases in one cycle — consider splitting for reviewability. Proceed anyway? [y/N]"* Allow user override.
- Never invoke more than one `/ship` in parallel. The manager agent holds repo-wide locks (tests, builds, migrations) that do not compose.

---

## Stage E — VERIFY (mandatory)

Invoke `/architect-review --scope <path> --full --force`.

Parse the new `state.json`:

- `features_vanished_this_run` **must be empty**.
- `findings` of kind `feature-regression` **must be empty**.
- `findings_open` should have dropped by at least the count of approved findings.

Outcome:
- **All three conditions met** → SOP CLEAN. Print:
  ```
  arch-imprv cycle complete at <scope>.
    Approved findings: <N>
    Resolved:          <M>
    Remaining open:    <findings_open>
    Feature regressions: 0  [zero-tolerance PASSED]
    Final review: <path-to-new-review>
  ```
- **Any condition failed** → SOP FAILED. Print the details. **Do not mark the cycle complete.** Exit non-zero. The user must address the blocker before `/arch-imprv` is considered done.

A Stage-E failure means the ship pipeline passed its own gates but introduced drift or a regression the gates missed. This is the backstop. Zero-tolerance is enforced here mechanically.

---

## Resumption

At the start of every invocation, check for in-progress plans:

```
plans = glob(".claude/plans/*.md") sorted by mtime
for plan in plans:
    read plan's Phases table
    for each phase, check if .claude/skills/<phase-slug>/ still exists
    compute: how many phases shipped (heuristic: git log -- <phase.touches> shows commits matching phase goal)
    if any_phase_pending:
        offer resumption
```

Present:
```
In-progress plan detected: <slug>
  [shipped] 1. <phase-1-slug>
  [shipped] 2. <phase-2-slug>
  [pending] 3. <phase-3-slug>
  [pending] 4. <phase-4-slug>

Resume at phase 3? [y/N/start-fresh]
```

- `y` → jump to Stage D at phase 3.
- `N` → exit, leave state alone.
- `start-fresh` → begin Stage A, treat the in-progress plan as stale (do NOT delete — only the user deletes phase-skills).

---

## Hard rules

1. **feature-regression is never skippable.** User cannot uncheck a MUST-DO in Stage B triage.
2. **ADR-required findings never enter the cycle.** Surface them with an explicit pointer to `docs/adr/` — they require human decision-making the skill cannot automate.
3. **Stage E is mandatory.** A cycle that doesn't pass Stage E is not complete, regardless of `/ship` outcomes.
4. **No parallel `/ship` invocations.** Serialize phases strictly.
5. **No auto-commits or auto-merges beyond what `/ship` already does.** This skill calls `/ship`; `/ship` owns the commit/merge contract.
6. **No silent phase-skill deletion.** Even after a successful cycle, leave phase-skills under `.claude/skills/` for the user to review/remove. Per your project memory hygiene: cleanup is the user's call.
7. **If Stage A produces zero findings, Stage B is skipped and the skill exits.** Do not run `/architect-plan` or `/ship` on an empty work item.
8. **Every `/ship` failure must be classified via the phase-skill's Test Impact map.** Unclassified failures mean the plan is broken — abort, do NOT press on with later phases. Silent attribution ("the test must have been wrong") is forbidden.
9. **A test classified as UNINTENDED (preserved feature regression) is a zero-tolerance blocker**, identical to a `feature-regression` finding. Stage E will re-surface it if the user bypasses this gate, so do not.

---

## Why this exists (vs. the user running the pieces manually)

- `/architect-review` produces findings — but the user has to remember which `state.json` to hand to `/architect-plan`.
- `/architect-plan --from-review ...` writes phase-skills — but the user has to ship each one in order and remember to re-verify.
- `/ship` executes — but has no concept of the review it was born from.
- **`/arch-imprv` is the SOP** — it wires these three together with the correct `--from-review` plumbing, the mandatory Stage E, and the zero-regression gate. Convenience, not new capability.

If any single stage feels off, you can still run it by hand — this skill does not lock you in.
