---
name: architectural-design
description: "Plan a multi-phase feature or refactor. Scans the relevant codebase, writes a phased implementation plan, decomposes each phase into a standalone skill under .claude/skills/, and returns the ordered /ship invocation sequence. PLANNER ONLY — never writes implementation code, never commits."
argument-hint: /architectural-design <one-sentence goal or path to spec>
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

**When NOT to use it:**
- Single-file bug fixes → just fix it.
- Already have an approved spec and only need ONE phase of work → use `/ship` directly with the `architect-design` agent.
- Read-only evaluation of existing code → use `/architectural-review`.

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

## Acceptance Criteria

- [ ] <testable criterion 1>
- [ ] <testable criterion 2>
- [ ] All existing tests pass.
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

## Guardrails

- **Never write to `backend/`, `frontend/`, `src/`, or any source path.** Only `.claude/plans/` and `.claude/skills/<phase-slug>/`.
- **Never run `git add`, `git commit`, or modify git state.**
- **Never run the application, tests, or migrations.**
- **If the goal requires touching a hot file** (listed in `CLAUDE.md`'s Critical Rules), the corresponding phase-skill must include a "Related components to read first" section enumerating every related file.
- **If a proposed phase-skill would overwrite an existing skill,** stop and ask the user how to disambiguate (rename or confirm overwrite).
- **Token discipline:** use Explore subagents for scanning. Do not Read every file in scope yourself.

## Failure modes to watch for

- **Phase inflation** (splitting one obvious commit into three phases) — if a phase's acceptance criteria are "file compiles," merge it up.
- **Phase conflation** (bundling DB + API + UI into one phase) — if two acceptance criteria test different subsystems, split it.
- **Hidden ordering** (Phase 3 quietly assumes Phase 2's internal data structure) — make the coupling explicit in `depends_on` or merge.
- **Copy-paste phase-skills** — every phase-skill must have distinct `touches`, `interface_changes`, and `acceptance`. If two look the same, the plan is wrong.

## Handoff chain

This skill → user runs `/ship /<phase-1>` → `architect-design` agent (single-phase design) → `implementer` → `tester` → `qa-critic` → user reviews → user runs next `/ship`.

This skill produces the entry point (the phase-skill that `/ship` consumes). It does not participate in execution.
