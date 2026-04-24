---
name: docs-thorough
description: "Deliver thorough, linearly-readable human docs for the current repo. Discover the codebase's elements, write per-element docs (or refresh existing docs using git history since each doc's last-modified timestamp), then assemble them in a linear reading sequence. Models the target docs on bpx-hub's docs/ layout — each file owns one topic; docs/README.md is the index and defines the read order."
---

# Deliver Thorough, Linear Docs

Produce a complete, top-to-bottom readable `docs/` tree for the current repo. Works in two modes:

- **Greenfield** — repo has no `docs/` (or only a `README.md`). Write each element's doc from scratch, then assemble.
- **Refresh** — repo already has docs. For each doc, walk git history since the doc was last modified and update the doc to reflect drift. Then re-verify the reading sequence stays linear.

**Reference layout:** bpx-hub's `docs/` is the template — see https://github.com/bpx-ai/bpx-hub/tree/main/docs for what "thorough + linear" looks like in practice (`README.md` index → `setup.md` → `architecture.md` → `configuration.md` → `api.md` → `deployment.md` → `operations.md` → `faq.md`). Adapt the set of files to what the target repo actually is; not every repo needs every file.

**This skill writes to documentation files.** It does NOT modify source code.

**Linearity contract:** doc N must be understandable with only knowledge from docs 1..N-1. Forward references are allowed (e.g. "details in §deployment") but forward *requirements* are not (a reader shouldn't have to jump ahead to understand the current doc). The final phase verifies and fixes this.

---

## Workflow

Run the phases in order. Do not skip the linearity pass at the end — that is where the "linear reading sequence" contract is actually enforced.

---

### Phase 1 — Discover the elements

Enumerate what this repo actually is and what it exposes. Capture this as a working outline before writing anything.

1. **Repo purpose (one paragraph).** Read `README.md`, `pyproject.toml` / `package.json` / `Cargo.toml` description, top-level source comments. Write a one-paragraph summary of what this repo is for and who the audience is. This becomes the lead paragraph of `docs/README.md`.

2. **Element inventory.** List every discrete "thing" a reader might need docs for. Typical categories (skip what doesn't apply):

   | Category | What it covers | Source signals to look for |
   |----------|----------------|----------------------------|
   | Purpose / what this is | High-level framing | `README.md`, top-level docstrings |
   | Setup / install | Getting it running locally | `Makefile`, `pyproject.toml`, `package.json`, `Dockerfile`, setup scripts |
   | Architecture | Subsystems, data flow, key protocols | Top-level source directories, `main.py` / `index.ts`, entry points |
   | Configuration | Env vars, YAML/TOML config, feature flags | `config.py`, `.env.example`, `config/*.yaml`, `settings.*` |
   | API / interface | How callers invoke this | FastAPI routers, CLI entry points, exported SDK surface, HTTP handlers |
   | Integration | How it talks to sibling repos / external services | HTTP clients, SDK imports, docker-compose service graph |
   | Deployment | Building, shipping, running in prod | `Dockerfile`, `deploy/`, `systemd` units, compose overlays |
   | Operations | Day-2: logs, metrics, backups, probes, alerts | `metrics.py`, `/health`, `/ready`, logging config, alert rules |
   | Security / auth | Authentication, authorization, secret handling | Auth middleware, token handling, secrets workflows |
   | Troubleshooting | Known failure modes + recoveries | Error handlers, retry logic, runbook hints |
   | FAQ / glossary | Jargon dictionary | Terms used in the above that readers would look up |

   For each element that applies, write a one-line description of what its doc will cover. If an element doesn't apply (e.g. a pure SDK has no deployment doc), say so explicitly — do not invent content.

3. **Reading order.** Sort the elements into linear reading order. The default order below works for most operational repos; reorder when the repo's audience differs:

   1. Purpose (index landing)
   2. Setup / install
   3. Architecture (so reader has a mental model before seeing knobs)
   4. Configuration
   5. API / interface
   6. Integration (how it plugs into the bigger system)
   7. Deployment
   8. Operations
   9. Security / auth (often cross-cuts — place where it makes most sense)
   10. Troubleshooting
   11. FAQ / glossary

   Write the chosen order into a scratch note. This becomes the `docs/README.md` table of contents in Phase 3.

4. **Sibling repos (if applicable).** If the repo is part of a larger system (e.g. one of the BPX repos), list the sibling repos and the interaction surface in one table. This goes near the top of `docs/README.md` so readers know where they are in the larger picture.

---

### Phase 2 — Write / refresh each element's doc

**Run this phase once per element, in the reading order from Phase 1.** Producing docs in the read order means each doc is written with awareness of exactly what prior docs have already established — no forward-knowledge assumptions.

#### 2A — Branch on existing vs new

For each element, check whether a doc already exists:

```bash
# Find the doc file, if any
ls docs/<element>.md 2>/dev/null
```

If **no doc exists** → go to §2B (Greenfield). If **a doc exists** → go to §2C (Refresh).

#### 2B — Greenfield: write from scratch

Draft the doc using this template. **Each element's doc is one file; resist the urge to split into subdirectories until the single file exceeds ~500 lines.**

```markdown
# <Element title>

<Lead paragraph: one sentence on what this doc covers, one on when to read it.>

## <Section 1>
…

## <Section N>
…

## See also
- [`prior.md`](prior.md) — context assumed by this doc
- [`next.md`](next.md) — where to go after this
```

Content rules (derived from what works in bpx-hub's docs):

- **Start with intent, not mechanics.** First section answers "what is this and what problem does it solve." Don't open with a command block.
- **Prefer concrete over abstract.** Name real file paths (`src/bpx_hub/config.py:SETTING_SPECS`), real commands (`make up`), real env var names (`HUB_API_TOKEN`). Not "the config module".
- **Single source of truth.** If a value lives authoritatively in code (e.g. `EXPECTED_SECRETS` in `secrets.py`), link to it and quote it; do not re-enumerate in the doc where it can drift.
- **Tables for dense lists.** Env vars, endpoints, metrics, error codes — always tables with columns (name, purpose, default, notes).
- **Commands in bash blocks.** Show the command, not a paragraph about the command.
- **No aspirational content.** Document what exists today. Flag future work as explicitly-labeled "roadmap" at the end of a doc if useful.
- **See also at the bottom.** Every doc ends with a `## See also` pointing to the prior doc (what is assumed) and the next doc (where to go next). This enforces linearity.

Typical section scaffolds per element:

- **setup.md** — Install tools → first-run → every-time flow → recovery scenarios (new machine, lost key, etc.)
- **architecture.md** — One-paragraph framing → subsystem table → key protocols (lifecycle diagrams, state machines) → cross-subsystem data flow
- **configuration.md** — Env vars table → YAML/TOML config files table → precedence / override rules → examples
- **api.md** — Endpoint table (method, path, auth, purpose) → per-endpoint detail sections → error code reference
- **deployment.md** — Deploy shapes (docker-compose / k8s / systemd) → reverse proxy → TLS → healthchecks → build pipeline
- **operations.md** — Health probes → metrics → logs → alerts → backups → capacity planning → applying-code-changes recipes
- **faq.md** — Q&A + glossary entries

#### 2C — Refresh: diff against git history since last modification

When the doc exists, don't rewrite it — update it where code has drifted. The procedure:

1. **Get the doc's last-modified timestamp.**
   ```bash
   DOC=docs/<element>.md
   LAST_MTIME=$(git log -1 --format=%ct -- "$DOC")
   LAST_DATE=$(git log -1 --format=%cI -- "$DOC")
   echo "Doc last touched: $LAST_DATE"
   ```

2. **Identify the related source paths.** Two signals:
   - **Path mentions in the doc.** Grep the doc for `src/...`, `config/...`, `scripts/...` style paths. Those are the files the doc explicitly documents.
     ```bash
     grep -oE '(src|config|scripts|deploy|dashboard)/[A-Za-z0-9_./-]+' "$DOC" | sort -u
     ```
   - **Topic heuristic.** Map the doc's topic to source paths (e.g. `operations.md` → `src/**/metrics.py`, `src/**/alerting/`, `src/**/backup.py`).

   Deduplicate; call this list `RELATED_PATHS`.

3. **List commits that touched those paths since the doc was last modified.**
   ```bash
   git log --since="$LAST_DATE" --oneline -- $RELATED_PATHS
   ```

4. **For each commit, decide: does this affect doc content?** Read the commit message and, where useful, `git show --stat <sha>`. Classify each commit as:
   - **Drift** — adds/changes/removes something documented in the doc. Queue an edit.
   - **Internal refactor** — no user-visible change. Skip.
   - **New element** — introduces something not in the doc but in this doc's scope. Queue a new section.

5. **Apply edits, noting what changed.** Keep a running list like:
   ```
   operations.md
     - [updated] backup rotation default 24 -> 48 (commit abc1234)
     - [added] new alert rule provider_circuit_open (commit def5678)
     - [removed] stale reference to legacy_metrics_endpoint (commit 7890abc)
   ```

6. **Cross-doc drift.** If the commit affects multiple docs (rare but happens), note it on each and ensure the phrasing stays consistent across files.

7. **Timestamp touch.** After editing, the doc's git mtime will advance naturally on commit — no manual touch needed.

**Do NOT rewrite whole sections that are still correct.** Surgical edits only; preserve voice and existing good content.

---

### Phase 3 — Assemble into a linear index

Write `docs/README.md` (or update the existing one). This file is the entry point and establishes the linear reading order.

Template:

```markdown
# <Repo> Documentation

<Lead paragraph from Phase 1: what this repo is + who reads these docs.>

## Read in order

1. [**Setup**](setup.md) — getting it running locally
2. [**Architecture**](architecture.md) — subsystems and data flow
3. [**Configuration**](configuration.md) — every env var and config file
4. [**API**](api.md) — how callers talk to this
5. [**Integration**](integration.md) — how this fits with <sibling repos>
6. [**Deployment**](deployment.md) — Docker, reverse proxy, TLS, health probes
7. [**Operations**](operations.md) — metrics, logs, alerts, backups, applying changes
8. [**Troubleshooting**](troubleshooting.md) — known failure modes
9. [**FAQ / Glossary**](faq.md) — jargon dictionary

## Jump-in table (skip to what you need)

| Doc | Read when |
|-----|-----------|
| setup.md | Standing up on a new machine, onboarding a teammate |
| architecture.md | Making a change that spans subsystems |
| configuration.md | Changing a knob or adding a new env var |
| api.md | Writing a client / consumer |
| deployment.md | Pushing to production |
| operations.md | Day-2: something's wrong, or tuning |
| faq.md | Hit a term you don't know |

## Sibling repos (if applicable)

| Repo | Role | Interaction |
|------|------|-------------|
| <repo> | <role> | <how it talks to this repo> |
```

Two access patterns are intentional:
- **Read in order** — onboarding narrative. Start here.
- **Jump-in table** — lookup-style for returning readers.

---

### Phase 4 — Linearity pass

Walk the docs in the order defined by `docs/README.md`. For each doc, check:

1. **Forward-requirement check.** Does the doc require knowledge from a *later* doc? Two ways this shows up:
   - A term is used without definition, and the definition is in a later doc.
   - A concept is referenced ("as seen in the scheduler") but the reader hasn't reached that subsystem yet.

   Fix either by: (a) moving the minimal necessary explanation into the current doc, or (b) reordering the index so the required doc comes first, or (c) adding a one-line inline gloss at first use and a forward link for detail.

2. **Backward-redundancy check.** Is this doc re-explaining something the earlier doc already covered? Delete the duplicate; link back instead.

3. **See-also consistency.** Each doc's `## See also` block should point at least to the previous doc (what's assumed) and the next doc (where to go). If it points forward to a doc that doesn't exist yet or has been renamed, fix.

4. **Path and code-reference validity.** Every `src/...`, `config/...`, `scripts/...` reference should exist. Run:
   ```bash
   grep -hoE '(src|config|scripts|deploy|dashboard)/[A-Za-z0-9_./-]+' docs/*.md | sort -u | while read p; do
     test -e "$p" || echo "BROKEN: $p"
   done
   ```

5. **Command validity (spot check).** Pick 3–5 commands shown in the docs and dry-run them (or verify they exist in `Makefile` / `package.json` scripts). Flag any that fail.

6. **Reorganize if needed.** If the forward-requirement check surfaces a circular or jumbled dependency between docs, update `docs/README.md`'s order AND update the `## See also` blocks of every affected doc. This is the only phase allowed to change doc ordering.

Produce a short linearity report:

```markdown
### Linearity pass

- ✓ setup.md → architecture.md — no forward requirements
- ✗ configuration.md → api.md — configuration.md references "request queue" before it's defined. Fix: move the one-line queue gloss into configuration.md §request-handling, leave the detailed protocol in api.md.
- ✓ …

Final order unchanged / changed to: [new order]
```

---

## Output contract

At the end of a run, the skill must have produced:

1. A populated (or refreshed) `docs/` tree with one file per element in linear order.
2. A `docs/README.md` index with both the linear sequence and the jump-in table.
3. Every doc ending with a `## See also` block linking at least the prior and next docs.
4. A short delivery summary printed to the user:
   ```
   docs-thorough report
     mode: greenfield | refresh
     files created: N
     files updated: N
     drift commits processed: N (refresh mode only)
     linearity pass: PASS | PASS-AFTER-REORDER
     broken path references: 0
   ```

---

## When to run this skill

- A repo has only a `README.md` and you want a full `docs/` tree that reads linearly.
- A repo's docs haven't been touched in weeks and the code has moved on (refresh mode).
- Onboarding a new teammate revealed gaps in the docs.
- After a milestone (major feature land, release cut) to sweep drift before publishing.

## When NOT to run this skill

- The docs live outside the repo (Notion, Confluence, GitBook) — this skill only writes to `docs/` in the current working directory.
- You just want to audit existing docs for staleness without rewriting — use `/hygiene` instead.
- You want to review source code quality — use `/simplify`.

## Notes for the author

- Model the target repo's docs on bpx-hub's tone: direct, concrete, single-source-of-truth, no aspirational content.
- Every doc should earn its place — if a section is just placeholder text ("TBD" / "Documentation coming soon"), delete the section; don't ship empty scaffolding.
- If a repo genuinely doesn't need one of the default elements (e.g. an SDK library has no deployment doc), omit it from both the file list and the index. Do not create empty files.
- The "linear reading sequence" is the contract — if you cannot satisfy it without reorganizing, reorganize. Do not ship docs that require the reader to hop around.
