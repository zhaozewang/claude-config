---
name: architect-plan
description: "Plan a multi-phase feature or refactor. Scans the relevant codebase, writes a phased implementation plan, decomposes each phase into a standalone skill under .claude/skills/, and returns the ordered /ship invocation sequence. PLANNER ONLY — never writes implementation code, never commits. Pairs with /architect-review (backward: audit drift in existing code)."
argument-hint: /architect-plan <one-sentence goal or path to spec>
user-invocable: true
context: fork
---

# Architectural Design

Turn a feature/refactor goal into an **executable plan of phase-skills** that can be shipped one at a time via `/ship`.

**What this skill does:**
1. Scans only the codebase regions relevant to the goal (via Explore subagent).
2. Produces a phased implementation plan.
3. Writes one `SKILL.md` per phase into `.claude/skills/<phase-slug>/` — each phase-skill is a self-contained spec.
4. Writes a top-level plan index to `.claude/plans/<slug>-<YYYY-MM-DD>.md`.
5. Prints the ordered `/ship <phase-slug>` sequence for the user to run.

**What this skill does NOT do:**
- Write implementation code. Phase-skills are **specs only**.
- Commit, push, or modify source files outside `.claude/`.
- Run tests, builds, or migrations.
- Execute any phase. The user runs `/ship <phase-slug>` themselves, in order.

**When to use it:**
- A goal touches ≥2 subsystems OR needs ≥2 independently-shippable chunks.
- You want a forcing function to think in commit boundaries before writing code.
- You want each phase to be reviewable and revertable on its own.
- **You are acting on an `/architect-review` finding** — invoke with `--from-review <path>` so feature preservation is mechanically enforced. Example: `/architect-plan --from-review docs/architecture-reviews/src-bpx_hub-scheduler/state.json "decouple routing from affinity cache"`. See "Feature preservation" below.

**When NOT to use it:**
- Single-file bug fixes → just fix it.
- Already have an approved spec and only need ONE phase of work → use `/ship` directly with the `architect-design` agent.
- Read-only evaluation of existing code → use `/architect-review`.

---

## Workflow

The skill runs in five phases. **Checkpoint with the user between phases 2, 3, and 4** — do not auto-proceed past them.

---

### Phase 1 — Intake

1. Read `$ARGUMENTS`. If empty or unclear, ask the user for:
   - A one-sentence goal ("Add X", "Refactor Y to Z", "Migrate from A to B").
   - Any existing spec (path to a markdown file or inline text).
   - Constraints (deadlines, backward-compat requirements, "must not touch subsystem X").
2. Derive a **slug** from the goal (kebab-case, ≤40 chars). This will be the `.claude/plans/` filename and the prefix for every phase-skill name.
3. Read `CLAUDE.md` (project root) if it exists. Note:
   - Documented subsystems, hot files, critical invariants.
   - Any `.claude/rules/` files — these are path-scoped constraints the plan must respect.
4. Confirm the slug + goal summary with the user in one line. Proceed on confirmation.

---

### Phase 2 — Targeted Scan

Delegate to an `Explore` subagent. Do **not** read the whole codebase yourself — that burns main context.

Send the Explore agent a prompt containing:
- The goal (verbatim).
- The list of documented subsystems from CLAUDE.md.
- A request for: **(a)** every file/module likely to be modified, **(b)** every file/module likely to be read for context only, **(c)** public contracts (APIs, DB tables, event types, prompt templates) that the goal will cross, **(d)** any existing half-built work in the same area (parallel implementations, feature flags, WIP branches referenced in CLAUDE.md "Known Issues").

Cap the Explore agent's response at ~400 words. It returns a structured inventory.

**Checkpoint:** Print the inventory to the user and ask: *"Does this capture the scope? Anything missing or out of scope?"* Adjust if needed. Proceed on approval.

---

### Phase 3 — Phase Plan

Author a plan with these properties:

- **3–8 phases.** Fewer is better. A phase must be small enough to ship in one review, large enough to be meaningful.
- Each phase has:
  - `slug` — kebab-case, `<feature-slug>-phase-<N>-<verb>` (e.g., `evidence-tree-phase-1-schema`).
  - `goal` — one sentence.
  - `touches` — list of files/modules this phase may modify.
  - `reads_only` — list of files the implementer must read for context.
  - `interface_changes` — API routes, DB columns, event types, function signatures added/modified/removed.
  - `depends_on` — prior phase slug(s), or `none` for the entry phase.
  - `acceptance` — 2–5 testable criteria a human can check.
  - `rollback` — how to revert this phase's changes if it ships broken.
- **Commit boundaries:** every phase must leave the system in a runnable state. No phase may depend on a subsequent phase to compile/start.
- **Migration ordering:** DB schema changes precede API changes precede frontend changes, unless the plan explicitly calls out a feature flag with rationale.
- **No hidden coupling:** if two phases must ship together, merge them.

Do NOT write phase-skill files yet.

**Checkpoint:** Print the phase list (slugs + one-line goals + dependency graph) and ask: *"Approve this phase breakdown, or should I resplit?"* Iterate until approved.

---

### Phase 4 — Decompose into Skills

For each approved phase, write `.claude/skills/<phase-slug>/SKILL.md`. Use this exact template:

```markdown
---
name: <phase-slug>
description: "<Phase N of <feature-slug>>: <one-sentence goal>. Depends on: <prior-slug or none>. Ships: <what changes>."
argument-hint: /ship /<phase-slug>
user-invocable: true
---

# <Phase N>: <Title>

**Goal:** <one sentence>

**Depends on:** <prior-slug or none>

## Scope

### Touches (may modify)
- `path/to/file1.py` — <what changes>
- `path/to/file2.ts` — <what changes>

### Reads only (for context)
- `path/to/file3.py` — <why>

### Out of scope
- <explicitly excluded work — name the phase that owns it>

## Interface Changes

<API routes, DB migrations, event types, function signatures — use subsections>

### API
### Database
### Events
### Prompts
### Frontend contracts

(Omit empty subsections.)

## Implementation Steps

1. <small, ordered, reviewable step>
2. <...>
N. <final verification step>

## Feature Preservation (zero tolerance)

List every feature from the inbound review's `feature_inventory` whose evidence anchors overlap with this phase's `Touches`. For each, list the anchors this phase must leave verifiable post-change. Any anchor removed or renamed requires a paired migration in the SAME phase (not a later one) and a matching update to the feature inventory cited in the PR description.

- `feat-<id>` — <human name>
  - Keep resolvable: `<file>:<lines>` (<source: route|done-list|cli|ui|flag|docstring>)
  - Keep resolvable: `<file>:<lines>` (...)
  - Migration in this phase if anchor changes: <exact rename/move and where the new anchor lands>

If this phase has NO overlap with any inventory feature, state: `No feature preservation obligations — this phase touches only internal-only code.` Do not omit the section.

## Test Impact (scope-aware attribution map)

Derive this table from the `test_anchors[]` of every feature listed under Feature Preservation above. The implementer MUST use this to classify any failing test during `/ship` as **intended** or **unintended**.

### Must stay green — a failure here is UNINTENDED
<tests covering features whose anchors this phase does NOT migrate — i.e. behavior is preserved exactly>
- `<test_id>` — covers `feat-<id>` — kind: `unit | integration | e2e`
- ...

### Expected to change — a failure here is INTENDED (update the test within this phase)
<tests covering features whose anchors this phase DOES migrate — behavior is changing by design>
- `<test_id>` — covers `feat-<id>` — reason: anchor `<file>:<lines>` moves to `<file>:<lines>`
- ...

### New tests added by this phase
<tests this phase introduces to cover new behavior or to re-pin a moved anchor>
- `<test_id>` — covers `feat-<id>` — added because: <reason>

### Out-of-scope tests — a failure here is UNINTENDED (scope violation)
Any test not listed in the three buckets above that fails during this phase is proof that the phase touched code it wasn't supposed to. STOP and report as `OUT_OF_SCOPE_TEST_FAILURE`.

## Acceptance Criteria

- [ ] <testable criterion 1>
- [ ] <testable criterion 2>
- [ ] **Every feature listed under Feature Preservation above is verifiable post-change via its updated anchors** (E2E scenarios pass, routes respond, CLI commands run, feature flags honored).
- [ ] **Every test in Test Impact → "Must stay green" passes unmodified.**
- [ ] **Every test in Test Impact → "Expected to change" has been updated, and the update is within this phase's `Touches`.**
- [ ] **No test outside the Test Impact map fails.** Unmapped failures are ship-blockers.
- [ ] `/architect-review --scope <scope> --full` run after this phase produces zero `feature-regression` findings AND zero `test_coverage_gap` findings for features in Feature Preservation.
- [ ] Build + lint pass (`/check` or project equivalent).

## Test Plan

- **Unit:** <what to add, where>
- **Integration:** <what to add, where>
- **Manual / browser:** <if UI changed, what flow to verify>
- **Eval:** <if audit logic or prompts changed — which eval cases>

## Rollback

<exact steps to revert: which migration to downgrade, which file to restore, which flag to flip>

## Handoff to Next Phase

**Invariants this phase guarantees** (next phase may rely on these):
- <...>

**Invariants this phase does NOT guarantee** (next phase must handle):
- <...>
```

**Quality gates for each phase-skill** (self-check before writing):
- [ ] Every file path in "Touches" and "Reads only" actually exists (or is explicitly marked `(new file)`).
- [ ] No implementation code — only specs, interfaces, and steps.
- [ ] Acceptance criteria are testable by a human without re-reading the plan.
- [ ] Rollback is concrete, not "git revert."
- [ ] The phase-skill is independently `/ship`-able — no references to other phase-skills' internals.

---

### Phase 5 — Plan Index + Handoff

1. Write `.claude/plans/<slug>-<YYYY-MM-DD>.md`:

   ```markdown
   # <Goal> — Architectural Plan — <YYYY-MM-DD>

   ## Goal
   <one paragraph>

   ## Scope Summary
   <inventory from Phase 2, trimmed>

   ## Phases

   | # | Slug | Goal | Depends on | Touches |
   |---|------|------|------------|---------|
   | 1 | <slug> | ... | none | ... |
   | 2 | <slug> | ... | <prior> | ... |

   ## Execution Order

   Run these in order. Do not skip ahead — each phase assumes its predecessor shipped.

   1. `/ship /<phase-1-slug>`
   2. `/ship /<phase-2-slug>`
   3. ...

   ## Rollback Strategy (whole feature)
   <how to back out if the feature is abandoned mid-stream>

   ## Notes
   - Phase-skills live under `.claude/skills/<slug>/`.
   - After all phases ship, consider deleting the phase-skills (per project memory: clean up completed skills).
   ```

2. Print a terminal-friendly summary to the user:

   ```
   Plan written: .claude/plans/<slug>-<date>.md
   Phases created: <N>
   Run in order:
     1. /ship /<phase-1-slug>
     2. /ship /<phase-2-slug>
     ...
   After each /ship completes and you've reviewed the diff, invoke the next.
   ```

3. **Stop.** Do not invoke `/ship`. Do not implement. Wait for the user.

---

## Feature preservation — zero tolerance

When invoked with `--from-review <path-to-state.json>`, this skill:

1. Reads the `feature_inventory` array (including each feature's `test_anchors[]`) from that `state.json`.
2. For every candidate phase it drafts in Phase 3, computes the intersection of `phase.touches` with each feature's `evidence_anchors`. A feature "belongs to" a phase if any anchor lies under a touched path.
3. Refuses to emit a phase-skill in Phase 4 unless its body contains a fully populated `## Feature Preservation` section listing every belonging feature by id, with explicit migration notes for any anchor the phase will move or rename.
4. Refuses to emit a phase-skill unless its body contains a fully populated `## Test Impact` section derived from the test_anchors of every belonging feature — sorted into four buckets (`Must stay green`, `Expected to change`, `New tests added`, `Out-of-scope`) per the phase-skill template.
5. Adds the full set of zero-tolerance checks to **every** phase's Acceptance Criteria.

### Deriving Test Impact from the inventory

For each belonging feature `f`, each of its `test_anchors[j]`:
- If the phase's migration notes say `f`'s anchors stay put → test goes under **Must stay green**.
- If the phase's migration notes say `f`'s anchors move/rename → test goes under **Expected to change**, and a migration note describes what to update in the test (new anchor path, new assertion).
- For any new anchor the phase introduces that wasn't in `f`'s prior anchors → add a placeholder **New test** entry.
- Any test that the critic flagged as a `test_coverage_gap` for a belonging feature → the phase MUST include a new test closing the gap (added under **New tests**). Don't let phased refactors ship without covering what was uncovered.

When invoked **without** `--from-review` — enumerate features AND their test anchors yourself using the same heuristics the critic uses. Missing the inventory is not a free pass; it just means you do the identification yourself. Be explicit in the plan about which signals you used so a future review can reconcile.

**The rule, stated once:** an architectural re-design that removes a feature without an accompanying ADR (`Status: accepted — supersedes <feature_id>`) is a ship-blocker. Architects plan, implementers execute — neither silently drops features. If a feature is being intentionally retired, the ADR comes first, before any phase that removes its anchors.

Structural findings from `/architect-review` with `effort: phased-refactor` are the canonical input to this skill. The review captures the inventory; this skill carries it forward as preservation gates; `/ship` executes with those gates green; next `/architect-review` run confirms zero regression.

---

## Guardrails

- **Never write to `backend/`, `frontend/`, `src/`, or any source path.** Only `.claude/plans/` and `.claude/skills/<phase-slug>/`.
- **Never run `git add`, `git commit`, or modify git state.**
- **Never run the application, tests, or migrations.**
- **If the goal requires touching a hot file** (listed in `CLAUDE.md`'s Critical Rules), the corresponding phase-skill must include a "Related components to read first" section enumerating every related file.
- **If a proposed phase-skill would overwrite an existing skill,** stop and ask the user how to disambiguate (rename or confirm overwrite).
- **Token discipline:** use Explore subagents for scanning. Do not Read every file in scope yourself.
- **Refuse to emit any phase-skill missing `## Feature Preservation`.** Zero tolerance — this is a structural check, not a best-effort nag.
- **Refuse to emit any phase-skill missing `## Test Impact`** when Feature Preservation is non-empty. Intended-vs-unintended test-failure attribution depends on this map existing; without it, `/ship` cannot classify failures and must halt.
- **Refuse to plan the removal of an inventory feature** unless an ADR retiring it already exists under `docs/adr/`. If the goal requires retiring a feature and no ADR exists, stop and tell the user to draft the ADR first.
- **Every test in `test_coverage_gaps[]` for a belonging feature must be closed by a phase in this plan.** If the plan can't close them all, split the goal and do the gap-closing cycle first.

## Failure modes to watch for

- **Phase inflation** (splitting one obvious commit into three phases) — if a phase's acceptance criteria are "file compiles," merge it up.
- **Phase conflation** (bundling DB + API + UI into one phase) — if two acceptance criteria test different subsystems, split it.
- **Hidden ordering** (Phase 3 quietly assumes Phase 2's internal data structure) — make the coupling explicit in `depends_on` or merge.
- **Copy-paste phase-skills** — every phase-skill must have distinct `touches`, `interface_changes`, and `acceptance`. If two look the same, the plan is wrong.

## Handoff chain

This skill → user runs `/ship /<phase-1>` → `architect-design` agent (single-phase design) → `implementer` → `tester` → `qa-critic` → user reviews → user runs next `/ship`.

This skill produces the entry point (the phase-skill that `/ship` consumes). It does not participate in execution.
