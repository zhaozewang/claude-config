---
name: hygiene
description: "Audit docs and Claude context files (README, CLAUDE.md, memory, rules, skills) for staleness, drift, and inconsistency. NOT for code — use /simplify for code quality. This skill covers documentation and project context only."
---

# Project Hygiene Audit

Audit project **documentation and Claude context files** for staleness, drift, contradictions, and clutter. Covers five targets: README, CLAUDE.md, memory files, rules, and skills.

**Scope: docs and context only.** This skill does NOT review source code quality, reuse, or efficiency — use `/simplify` for that. `/hygiene` ensures the *instructions and documentation around the code* stay accurate.

**This skill can write to documentation and context files.**

## Workflow

Run all five audits in order below. Collect findings into a single report. Only apply fixes after the user approves.

---

### Phase 1: Discovery

Find all auditable files:

```bash
echo "=== CLAUDE.md variants ==="
find . -name "CLAUDE.md" -o -name ".claude.local.md" 2>/dev/null | head -20

echo "=== README ==="
ls README.md README.rst README 2>/dev/null

echo "=== Rules ==="
ls .claude/rules/*.md 2>/dev/null

echo "=== Skills ==="
find .claude/skills -name "SKILL.md" 2>/dev/null

echo "=== Memory ==="
ls ~/.claude/projects/*/memory/*.md 2>/dev/null
```

Also check git status for deleted/untracked skill files — these are orphans that need cleanup.

---

### Phase 2: Audit Each Target

#### 2A. README.md

Check for drift between README and actual project state:

1. **Commands** — Run each command listed in README to verify it works (dry-run where possible). Flag commands that fail or reference missing tools.
2. **File paths** — Verify every path mentioned in README exists (`src/`, `config/`, etc.).
3. **Dependencies** — Cross-check listed tech stack against `pyproject.toml` dependencies and `dashboard/package.json`.
4. **Badges/links** — Check that any badge URLs or links resolve (skip external links, just flag them).
5. **Feature claims** — Compare "features" or "what this does" text against actual implemented code. Flag claims about unimplemented features.

#### 2B. CLAUDE.md

Check for accuracy and currency:

1. **Commands section** — Verify each command in the Commands block actually works by dry-running them.
2. **Architecture section** — Verify listed subsystem directories exist and descriptions match actual module contents.
3. **Code conventions** — Spot-check 2-3 source files to confirm conventions are actually followed (e.g., "async everywhere", "Pydantic models for all data").
4. **Key gotchas** — Check if any gotchas have been resolved by recent commits (e.g., "command queue is in-memory" may now be persisted).
5. **Implementation status** — This is the highest-value check. For each `[ ]` unchecked item:
   - Search git log for commits that implement it: `git log --oneline --all --grep="<keyword>"`
   - Search source code for evidence it exists: grep for relevant modules, decorators, config keys
   - If implemented, flag it as stale (should be `[x]`)
6. **Implementation status (done)** — For each `[x]` or listed "Done" item, verify it still exists and hasn't been reverted.
7. **@ imports** — Verify each `@path` reference points to a file that exists.
8. **Stale references** — Flag mentions of files, modules, or config that no longer exist.

Score CLAUDE.md on this rubric (each out of 20, total /100):

| Criterion | Weight | What to check |
|-----------|--------|---------------|
| Commands accuracy | /20 | Do listed commands work? |
| Architecture accuracy | /20 | Do paths and descriptions match code? |
| Implementation status currency | /20 | Are checkboxes up to date? |
| Conventions accuracy | /20 | Are conventions actually followed? |
| Conciseness & signal | /20 | No verbose filler, every line earns its place |

#### 2C. Memory Files

Audit `~/.claude/projects/*/memory/` for the current project:

1. **MEMORY.md index** — Check each entry links to a file that exists. Flag broken links.
2. **Individual memory files** — For each `.md` file:
   - Check frontmatter has required fields: `name`, `description`, `type`
   - Check `type` is one of: `user`, `feedback`, `project`, `reference`
   - **Staleness check**: If memory references a file path, verify it exists. If it references a function or config key, grep for it.
   - **Duplicate check**: Flag memories with overlapping descriptions or content.
   - **Project memories**: These decay fast. Flag any `type: project` memory older than 30 days (check git log for when it was last modified).
3. **MEMORY.md hygiene** — Verify it's under 200 lines (truncation risk). Flag if approaching limit.

#### 2D. Rules

Audit `.claude/rules/*.md`:

1. **File path references** — Verify any paths mentioned in rules point to existing files.
2. **Code pattern references** — If a rule says "use X pattern" or "call X function", verify X exists in the codebase.
3. **Contradiction check** — Flag if any rule contradicts CLAUDE.md or another rule.
4. **Relevance** — Flag rules that describe patterns not found anywhere in the codebase (may be aspirational or stale).

#### 2E. Skills

Audit `.claude/skills/*/SKILL.md`:

1. **Git status** — Flag skills that are deleted in git but not committed (orphans from `git status`).
2. **Untracked skills** — Flag skill directories that exist on disk but aren't tracked by git.
3. **Staleness** — For each skill:
   - If it references a roadmap item, check if that item is now complete
   - If it contains implementation instructions for something already built, flag as completed/stale
4. **Frontmatter** — Verify each SKILL.md has `name` and `description` in frontmatter.
5. **Skill-to-CLAUDE.md consistency** — If CLAUDE.md references skills (e.g., "see skills for implementation prompts"), verify the referenced skills exist.

---

### Phase 3: Report

Output a single structured report. This MUST be shown before any changes are made.

```markdown
## Project Hygiene Report

**Date:** YYYY-MM-DD
**Files audited:** N

### Summary
| Target | Status | Issues |
|--------|--------|--------|
| README.md | OK / NEEDS UPDATE | N issues |
| CLAUDE.md | SCORE/100 (GRADE) | N issues |
| Memory | OK / NEEDS CLEANUP | N issues |
| Rules | OK / HAS DRIFT | N issues |
| Skills | OK / HAS ORPHANS | N issues |

### Findings

#### README.md
- [STALE] Command `X` no longer works because...
- [DRIFT] Claims feature Y but it's not implemented...
- [OK] Tech stack matches dependencies

#### CLAUDE.md (Score: XX/100)
| Criterion | Score | Notes |
|-----------|-------|-------|
| Commands accuracy | X/20 | ... |
| Architecture accuracy | X/20 | ... |
| Implementation status | X/20 | ... |
| Conventions accuracy | X/20 | ... |
| Conciseness | X/20 | ... |

**Stale checklist items:**
- [ ] "Item X" — implemented in commit abc1234 (YYYY-MM-DD)
- [ ] "Item Y" — module exists at src/bpx_hub/y.py

**Stale gotchas:**
- "Command queue is in-memory" — persistence added in commit def5678

#### Memory
- [BROKEN LINK] MEMORY.md references `foo.md` but file doesn't exist
- [STALE] `project_bar.md` — references removed module, last modified 45 days ago
- [DUPLICATE] `feedback_x.md` and `feedback_y.md` overlap significantly
- Index size: N/200 lines

#### Rules
- [DRIFT] `database.md` says "use migrate_v1_to_v2 pattern" but no migrations exist yet
- [OK] `scheduler.md` matches implementation

#### Skills
- [ORPHAN] `implement-X/SKILL.md` deleted in git but not committed
- [COMPLETED] `implement-Y/SKILL.md` describes work already done in commit abc1234
- [UNTRACKED] `new-skill/` exists but isn't git-tracked
```

---

### Phase 4: Fix (Auto-Apply Safe Changes)

Apply fixes automatically in this order. Do NOT stop to ask the user for approval — these are documentation and context files, not code. The agent knows the current code state better than the user does.

**Auto-apply (safe — always apply):**
1. **CLAUDE.md** — Update checklist items (`[ ]` → `[x]`), remove stale gotchas, fix broken `@` imports, update architecture descriptions to match current code.
2. **README.md** — Fix stale commands, update feature descriptions, correct file paths.
3. **Memory** — Delete stale/duplicate memory files. Update MEMORY.md index to remove broken links.
4. **Skills** — Delete orphaned/completed skill directories.

**Flag but do NOT auto-fix:**
5. **Rules** — Rules affect code generation behavior. Log what's stale but leave them for the user to review later. Include in the report.

After applying, show a summary of what was changed (not a diff per file — just a list).

---

## When to Run This Skill

- After a batch of features lands (P0/P1 roadmap completion)
- Before starting a new project phase
- When onboarding a new contributor
- Monthly, as a hygiene check
- When context feels "off" — Claude making wrong assumptions may indicate stale CLAUDE.md or memory
