---
name: architect-review
description: "Periodic architectural drift audit for ONE scope. Reads stated architecture (CLAUDE.md, .claude/rules/, docs/architecture.md, docs/adr/) against the code, reports drift with a navigation header pointing at the parent scope and at every child scope ranked by drift pressure. Anchored to a git commit — second run on the same scope is incremental (only re-verifies what changed). READ-ONLY: writes only to docs/architecture-reviews/. No auto-recursion — the user drives traversal."
argument-hint: "[--scope <path>] [--force] [--full]"
user-invocable: true
context: fork
---

# Architecture Review — one scope at a time, incremental, user-navigated

Pair with `/architect-plan` (forward: plan a new feature or refactor). This skill is the backward half: take a scope, diff Intent vs Reality, record the result, and tell the user what to review next.

## What this skill does

1. Resolve the scope (arg or default = repo root).
2. Load prior state for this scope, if any.
3. Decide **full** vs **incremental** via `git diff`.
4. Gather Intent sources, narrowing with scope.
5. Gather Reality artifacts (dep graph, public surface, file list, churn, size).
6. Delegate analysis to the **`architecture-critic`** agent.
7. Write a timestamped, commit-anchored report prefixed with a **navigation header**.
8. Update `state.json` and `_index.md` atomically.
9. Print the navigation header to the user so they can copy the next command.

## What this skill does NOT do

- Does NOT modify source code. Ever. Only writes under `docs/architecture-reviews/`.
- Does NOT recurse. One invocation reviews one scope. The report lists children with scores and literal commands; the user runs the next one.
- Does NOT propose code changes. It produces **findings**; remediation goes through `/architect-plan` for structural work or straight to implementation for one-PR cleanups.
- Does NOT auto-invoke `/architect-plan` or any other skill.

## When to use it

- A subsystem has had a burst of feature work and you want to check it hasn't drifted from CLAUDE.md / rules.
- You're about to start a refactor and want a baseline of what's wrong before changing anything.
- A rule file was updated; you want to know what code now violates it.
- Periodic hygiene at phase boundaries (not on a wall-clock cron — drift is bursty).

## When NOT to use it

- Per-PR review → use the `code-review` plugin.
- Pure doc/context staleness → use `/hygiene`.
- Code-smell cleanup within a single change → use `/simplify`.
- Planning a new feature → use `/architect-plan`.

---

## Invocation

```
/architect-review                                    # scope = repo root ("global")
/architect-review --scope src/bpx_hub/scheduler
/architect-review --scope src/bpx_hub/scheduler/routing.py
/architect-review --force                            # re-review even with zero diff
/architect-review --full                             # ignore incremental, full scan
```

---

## Storage layout

All state and reports live under `docs/architecture-reviews/`:

```
docs/architecture-reviews/
├── _index.md                                 # index of every reviewed scope
└── <scope-slug>/
    ├── state.json                            # machine-read, atomic writes
    ├── review-YYYY-MM-DD-<shortsha>.md      # full review
    └── delta-YYYY-MM-DD-<shortsha>.md       # incremental delta (may be absent)
```

**Scope slug rule:** repo-relative path, `/` → `-`, `.` → `_`. Root → `global`. Examples:
- `.` → `global`
- `src/bpx_hub/scheduler` → `src-bpx_hub-scheduler`
- `src/bpx_hub/scheduler/routing.py` → `src-bpx_hub-scheduler-routing_py`

---

## Workflow

### Step 1 — resolve scope

- If `--scope` given, validate it exists (file or directory under the repo). Error out if not.
- Otherwise, scope = repo root, slug = `global`.
- Compute `scope_kind`:
  - repo root → `global`
  - any directory → `subsystem`
  - single file → `module`
- Compute `parent_scope`: the directory one level up (or `none` at root).

### Step 2 — resolve Intent sources (narrowing with scope)

Read in this order. Missing files are silently skipped:

1. **Always:** root `CLAUDE.md`, every `.claude/rules/*.md`, `docs/architecture.md`, every `docs/adr/*.md`.
2. **If subsystem named X:** the section of root CLAUDE.md that names X + `.claude/rules/<X>.md` (if present) + docstrings of the scope's top-level files.
3. **If module:** file docstring, class docstrings, inline invariant comments, and the tests that exercise it (tests document expected behavior).

Intent files are **also inputs to the diff** in Step 4 — a rule change with no code change still triggers re-verification.

### Step 3 — gather Reality artifacts

Cheap, deterministic. Write to temp files the critic agent can read.

- **File list under scope**, respecting `.gitignore`. Exclude: `tests/`, `node_modules/`, `dist/`, `build/`, generated/vendored dirs.
- **Import graph.** Python: a simple `ast`-based pass (parse, collect `import` and `from … import`). TypeScript: regex-based pass over `import` / `require` statements. Fallback for other languages: `grep -E '^(import|from|require|use )'`.
- **Public surface:** route handlers (FastAPI `@app.*` / `@router.*` decorators), CLI entries (`argparse`, `click`, etc.), exported symbols (`__all__`, top-level class/def), env vars read (`os.getenv`, `os.environ`).
- **Churn:** `git log --since=<last_commit> --oneline -- <scope>` → count + touched files. If no prior state, use the last 30 days instead.
- **Size:** LOC per direct child, file count, symbol count.

### Step 4 — decide full vs incremental

Load `docs/architecture-reviews/<scope_slug>/state.json` if it exists.

```
if no state.json or --full:
    mode = "full"
else:
    code_changes   = git diff --name-only <last_commit>..HEAD -- <scope>
    intent_changes = git diff --name-only <last_commit>..HEAD -- \
                       CLAUDE.md .claude/rules/ docs/architecture.md docs/adr/
    if len(code_changes) == 0 and len(intent_changes) == 0 and not --force:
        print "No changes since <last_commit> (<date>). Skipping — rerun with --force to re-verify."
        exit 0
    scope_files = tracked files under scope
    pct = len(code_changes) / max(1, len(scope_files))
    mode = "full" if pct > 0.15 else "incremental"
```

Print the decision: e.g. `mode=full (first run)` or `mode=incremental (3 code files, 1 intent file changed since e3c8a62)`.

**Edge case — commit not in history:** if `state.json.last_commit` is not reachable from HEAD (force-push / rebase), warn, treat as first run, and keep the old `state.json` archived as `state.json.bak-<iso>` so the user can reconcile manually.

**Edge case — scope renamed:** run `git log --follow --name-only <scope>` to detect renames since `last_commit`. If detected: move the old `<scope-slug>/` directory to the new slug, note the rename in the new report's navigation header, continue.

### Step 5 — invoke the critic

Call the `architecture-critic` agent with the input contract defined in its file. Pass:
- `scope`, `scope_kind`, `parent_scope`
- `intent_sources` (absolute paths)
- `reality_artifacts` (paths to temp files)
- `prior_findings` (parse the JSON block of the most recent review file in this scope's directory; `[]` if none)
- `diff`: `{ mode, last_commit, head_commit, changed_files, changed_intent_files }`

### Step 6 — write the report

The critic returns a single markdown response: a ```json block followed by a markdown body. Validate the JSON against the contract. **Reject any finding without a `file:line` citation** — re-prompt the critic for it.

Produce the final file by **prepending a mechanical navigation header**, then the executive summary, then the critic's markdown body, then the ```json block fenced for machine parsing on next run.

Navigation header template:

```markdown
# Architecture review — <scope>
Commit:  <head_short>  ·  <ISO UTC timestamp>
Mode:    full | incremental (delta from <last_commit>)

Parent:
  <parent_scope>  → /architect-review --scope <parent_scope>
  (or "none — this is the repo root")

Children (ranked by drift pressure):
  <score>  <child_path>      → /architect-review --scope <child_path>
  <score>  <child_path>      → /architect-review --scope <child_path>
  ...
  (N children below threshold 0.10 — listed in appendix)

Previous reviews of this scope:
  <YYYY-MM-DD>  <shortsha>   (<file>)
  ...
```

Executive summary (≤ 12 lines):
- claims: total / holds / drifted / unknown / stale
- findings: new / carried-forward / resolved / open total
- top 3 findings by severity (id + one-line statement)

Report filename:
- full → `review-YYYY-MM-DD-<shortsha>.md`
- incremental → `delta-YYYY-MM-DD-<shortsha>.md` (only changes since last review; carry-forward findings listed by id only, not restated in full)

### Step 7 — update state.json and _index.md (atomic)

Write `state.json` using write-then-rename:

```json
{
  "scope": "src/bpx_hub/scheduler",
  "scope_slug": "src-bpx_hub-scheduler",
  "scope_kind": "subsystem",
  "parent": "src/bpx_hub",
  "last_commit": "9f12aa1",
  "last_run_at": "2026-04-22T14:05:00Z",
  "findings_open": 3,
  "findings_resolved_this_run": 2,
  "feature_regressions_open": 0,
  "children_discovered": [
    { "path": "src/bpx_hub/scheduler/routing.py", "drift": 0.82, "covered_by_intent": true }
  ],
  "feature_inventory": [
    {
      "id": "feat-route-post-v1-acquire",
      "name": "POST /v1/acquire",
      "evidence_anchors": [
        { "file": "src/bpx_hub/api/client_routes.py", "lines": "42-98", "source": "route" },
        { "file": "CLAUDE.md", "lines": "180", "source": "done-list" }
      ],
      "test_anchors": [
        { "test_id": "tests/e2e/test_acquire.py::test_happy_path", "kind": "e2e" },
        { "test_id": "tests/unit/test_client_routes.py::test_acquire_returns_lease", "kind": "unit" }
      ],
      "first_seen_commit": "a1b2c3d",
      "last_verified_commit": "9f12aa1"
    }
  ],
  "test_coverage_gaps": [],
  "features_vanished_this_run": [],
  "reviews": [
    { "date": "2026-04-22", "commit": "9f12aa1", "mode": "incremental", "file": "delta-2026-04-22-9f12aa1.md" }
  ]
}
```

Update `docs/architecture-reviews/_index.md` — a table with columns: `Scope | Last review | Mode | Open findings | Drift of riskiest child | Report`. Sort by "last reviewed" descending. Create the file with a stub header if it doesn't exist.

### Step 8 — print the navigation header to the user

At end of run, print **only** the navigation header and a line of executive summary (not the whole report) so the user sees exactly:
- parent command
- ranked child commands
- open findings count + top-3
- path to the full report on disk

---

## Drift pressure — defined explicitly (tune per repo)

Used by the critic in its Phase 7 and surfaced in the navigation header. Kept in this skill file so the weights are discoverable and tuneable:

```
drift_pressure(c) =
    0.35 * open_findings_pointing_at_c / max(1, claims_at_this_scope)
  + 0.25 * log10(1 + commits_touching_c_since_last_review)
  + 0.20 * inbound_edges_to_c / max(1, total_inbound_edges_in_scope)
  + 0.10 * loc(c) / max(1, total_loc_in_scope)
  + 0.10 * (1 if c has no Intent source else 0)
```

Children with `drift < 0.10` appear only in the appendix, not the main header. Adjust weights or threshold if the scores feel wrong for this repo — the critic reads them from here.

---

## Feature inventory — zero-tolerance regression

An architectural drift audit is incomplete without knowing *what features exist*. On every run the critic builds a **feature inventory** for the reviewed scope and reconciles it against the prior run. **A feature that vanishes between runs is a critical regression finding and is NEVER auto-closed.**

### What counts as a feature (heuristics, in priority order)

1. **Public route handlers** — FastAPI `@app.*` / `@router.*`, Flask routes, tRPC procedures, GraphQL resolvers.
2. **Explicit catalog entries** — lines under `## Done`, `## Implementation Status`, `## Features` in CLAUDE.md / README / `docs/architecture.md`. On repos that maintain this list (bpx-hub does), it is the authoritative feature list.
3. **E2E test scenarios** — file names under `e2e/`, `tests/e2e/`, `integration/`; top-level `describe` blocks.
4. **CLI subcommands** — `argparse` / `click` / `commander` definitions.
5. **UI pages / flows** — React Router routes, Next.js pages, named dialogs.
6. **Feature flags** — any config key that gates a capability behind on/off.

Each detected feature records `{ id, name, evidence_anchors[], test_anchors[], first_seen_commit, last_verified_commit }`. The `id` is a deterministic slug (e.g. `feat-route-post-v1-acquire`) so reconciliation is stable across runs. Cross-reference multiple sources per feature where possible — a feature backed by a route AND a CLAUDE.md line AND an E2E scenario is robustly identified; one backed only by a docstring is fragile.

### Scope-aware test coverage (`test_anchors`)

Separate from evidence anchors, every feature carries a `test_anchors[]` list of the tests that cover it, each tagged `unit | integration | e2e`. The critic builds this map heuristically (path mirroring, name matching, pytest markers, E2E describe blocks). Features the critic can't map get listed in a scope-level `test_coverage_gaps[]` array — surfaced as medium-severity `test_coverage_gap` findings so the user knows which features are flying blind.

**Why this matters for downstream work:** `/architect-plan` uses `feature_inventory[i].test_anchors` to compute the **Test Impact** of every phase-skill it writes — which tests must stay green (feature preserved), which tests are expected to change (feature migrated), which are new. `/ship`'s implementer reads that Test Impact map to classify any failing test as **intended** (pre-approved change) or **unintended** (scope violation or regression) without guessing.

### Reconciliation (zero-tolerance in mechanical form)

On every run with prior state:
- Feature in both old and new inventory → update `last_verified_commit = head_commit`.
- Feature new this run → add with `first_seen_commit = head_commit`. Informational, not a finding.
- Feature in old but not in new AND no ADR retiring it → emit `kind: feature-regression` at severity `critical`, `effort: phased-refactor`. **The skill REFUSES to mark this finding as resolved unless a matching ADR exists.**
- Feature in old but not in new AND ADR `Status: accepted — supersedes <feature_id>` exists under `docs/adr/` → mark `retired`, cite the ADR, no finding.

### state.json extension

```json
{
  ...
  "feature_inventory": [
    {
      "id": "feat-route-post-v1-acquire",
      "name": "POST /v1/acquire — client lease acquisition",
      "evidence_anchors": [
        { "file": "src/bpx_hub/api/client_routes.py", "lines": "42-98" },
        { "file": "CLAUDE.md", "lines": "180" },
        { "file": "e2e/scenarios/happy_path.py", "lines": "1-60" }
      ],
      "first_seen_commit": "a1b2c3d",
      "last_verified_commit": "9f12aa1"
    }
  ],
  "features_vanished_this_run": [
    { "id": "...", "last_verified_commit": "e3c8a62", "finding_id": "F-REG-001" }
  ]
}
```

### Detection is not prevention — handoff to `/architect-plan`

This skill **detects** feature drift after the fact. **Preventing** regression *during* an architectural re-design is `/architect-plan`'s job. The pair works like this:

1. `/architect-review --scope X` captures today's feature inventory for scope X.
2. `/architect-plan --from-review docs/architecture-reviews/<slug>/state.json` reads that inventory and writes per-feature preservation gates into every phase-skill.
3. `/ship <phase>` executes with those gates as acceptance criteria.
4. Next `/architect-review --scope X` reconciles — any feature missing without an ADR is a ship-blocking regression finding.

Do not act on structural review findings without going through `/architect-plan`. That is where the preservation gates get written.

---

## Hard rules

1. READ-ONLY on source code. Only writes under `docs/architecture-reviews/`.
2. Every finding the critic returns **must** cite `file:line`. The skill validates before writing the report; if any finding lacks citation, re-prompt the critic.
3. If `state.json` exists but points at a commit not reachable from HEAD, warn, archive the old state, treat as first run.
4. If the scope was renamed/moved, migrate the slug directory rather than deleting.
5. No auto-recursion. No auto-remediation. No code edits. No commits.
6. Both code diff and intent diff drive the incremental decision. A rule change with no code change still triggers re-verification.
7. If the critic produces `undocumented-intent` as its first and only finding, halt further analysis at this scope: there is no ruler to measure against. Report states "propose an ADR before re-running." Don't fabricate invariants.
8. **Feature regression is critical and non-closable without an ADR.** `feature-regression` findings stay open across runs until the user writes an ADR whose `Status:` line explicitly retires the feature (`Status: accepted — supersedes <feature_id>`). Zero tolerance. No exceptions.
9. **Feature inventory is carry-forward by default.** A feature whose evidence anchors weren't touched by this run's diff keeps its prior `last_verified_commit` unchanged — it wasn't re-verified this run, don't claim it was.
10. **Refuse to run in incremental mode when `features_vanished_this_run` would be non-empty based on the diff alone.** If the diff deletes anchors of any prior inventory entry, force `mode = full` and re-scan comprehensively — incremental mode is for small, safe changes, not for detecting regressions that just landed.

---

## Handoff chain

- Structural finding with `effort = phased-refactor` → report ends with: *"Structural finding F-XXX requires a multi-phase refactor. Hand off to `/architect-plan` with this finding as the goal."* Do not auto-invoke.
- One-PR cleanup (`effort = one-pr`) → user can address directly via `/ship` or an implementer pass.
- `undocumented-intent` → user drafts an ADR under `docs/adr/` and re-runs this skill.
- `undocumented-convention` → candidate ADR text is included in the report body for user review.

This skill produces evidence and navigation. The user drives every next step.
