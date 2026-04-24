---
name: preflight
description: "Production-readiness gate for web applications. Discovers every intended feature from docs + routes, drives the live app in a real browser as a user, captures systematic screenshots + visual-bug heuristics, reproduces failures, and emits a READY / WARN / BLOCKED verdict. Run before promoting to production — NOT after every ship. Complements /ship (which is feature-scoped, DOM-level) with a holistic, visual, user-POV pass."
argument-hint: /preflight [--scope <area>] [--url <override>] [--no-launch]
user-invocable: true
---

# /preflight — Production-readiness gate

This skill answers one question: **"If I promote this to production right now, will real users see a broken product?"**

It is deliberately **separate from `/ship`**. `/ship` delivers one feature correctly (DOM, tests, types). `/preflight` sweeps the whole surface the user touches — every page, every toggle, every state — and flags visual / behavioural regressions `/ship` cannot see because it doesn't run the app.

## When to use

- Before promoting a branch to production / tagging a release.
- After merging several `/ship` runs, to catch cross-feature regressions.
- When the team says "the dashboard feels off" but no single test is red.
- After a dependency bump (React, Tailwind, shadcn, Vite, etc.).

## When NOT to use

- After every single commit — it's slow on purpose.
- As a unit-test replacement — this is end-to-end visual QA, not logic QA.
- On non-interactive projects (pure CLIs, libraries). This skill assumes a browser-renderable UI.

---

## Preconditions (fail fast)

Before doing anything, verify:

1. **Project is a web app.** Look for `dashboard/`, `web/`, `frontend/`, `app/`, or top-level `package.json` with a dev server. If none → abort with a clear message: "No web UI detected — /preflight is for browser apps."
2. **Dev server is reachable.** Read `CLAUDE.md` for the documented port. Probe it:
   ```bash
   curl -sSf http://localhost:<port> -o /dev/null && echo UP || echo DOWN
   ```
   If DOWN and `--no-launch` was not passed, ask the user whether to start it (`make dev`, `npm run dev`, etc.). Never auto-start without confirmation — dev servers have side effects.
3. **Playwright MCP is available.** The `qa-browser` agent drives Playwright. If those tools aren't wired into this session, stop and tell the user to enable Playwright MCP before retrying.
4. **Artifact directory is writable.** All output goes under `./qa-runs/<ISO-timestamp>/`. Create it and append the path to `.gitignore` if that file exists and doesn't already ignore `qa-runs/`.

---

## Run layout

Every invocation produces one run directory:

```
./qa-runs/<YYYYMMDDTHHMMSS>/
├── 00_meta.json            # commit sha, scope, CLAUDE.md hash, cli flags
├── 01_features.md          # feature inventory (Phase 1)
├── 02_workflows.md         # user workflow scripts (Phase 2)
├── 03_observations.jsonl   # one JSON line per step captured in Phase 3
├── 04_bug_report.md        # triaged bugs + repros (Phase 4)
├── 05_verdict.json         # {status: READY|WARN|BLOCKED, counts: {...}}
└── screenshots/
    ├── <feature-slug>/
    │   └── <NNN>-<step>-<variant>.png
    └── bugs/
        └── <bug-id>/
            ├── before.png
            ├── after.png
            └── repro.md
```

`<timestamp>` is UTC, sortable. Never overwrite a prior run — each invocation is its own immutable record so runs can be diffed over time.

---

## Phase 1 — Feature inventory

**Goal:** a complete, de-duplicated list of every feature a user can exercise. This is the source-of-truth the later phases test against.

Pull from, in order:

1. **`CLAUDE.md`** — look for "Done" / "Implementation Status" / "Features" sections. Every bullet is a candidate feature.
2. **Routing config** — the frontend router (React Router, Next.js app dir, Vite route files, `App.tsx`, nav components). Each route is a candidate page.
3. **Nav / menu components** — whatever the user clicks to move around. These reveal features that aren't on a top-level route (modals, drawers, tabs, tooltips).
4. **Recent commits** — `git log --oneline -n 40` for things shipped but not yet in `CLAUDE.md`.

For each feature, capture:

```yaml
- id: nodes-rotate-token                # kebab-case slug, stable across runs
  name: Rotate node token
  surface: page: /nodes → row action "Rotate"
  states:                               # every toggle/variant a user can hit
    - empty: no nodes registered
    - populated: ≥1 node present
    - pending-token: unbound token visible
  auth: admin bearer required
  expected: dialog opens → new one-line install command shown → copy button works
  source: CLAUDE.md "Node onboarding phase 3" + dashboard/src/components/RotateTokenDialog.tsx
```

Write the full list to `01_features.md`. **Do not skip auth-gated features** — include them, they will be exercised in Phase 3 using whatever auth mode the app supports (tokens in localStorage, CF Access header, dev-mode bypass — check `CLAUDE.md` and `.claude/rules/auth.md` if present).

If a feature is listed in `CLAUDE.md` but has no surface you can find in the code, flag it as `status: undiscoverable` and continue. Those become WARN-level findings in the verdict.

**Scope narrowing:** if the user passed `--scope <area>`, filter the feature list to ids/surfaces matching that area (substring match on `id`, `surface`, or source path). Default is no filter — everything.

---

## Phase 2 — Workflow scripts

**Goal:** turn each feature into a user-POV click-path that Phase 3 can execute mechanically.

For every feature, every state, write one workflow block:

```yaml
- feature_id: nodes-rotate-token
  variant: populated
  steps:
    - navigate: /nodes
    - wait_for: "table tbody tr"
    - screenshot: populated-list
    - click: 'tr:first-child button[aria-label="Rotate"]'
    - wait_for: '[role="dialog"]'
    - screenshot: dialog-open
    - assert_visible: 'code:has-text("curl")'
    - click: 'button:has-text("Copy")'
    - assert_visible: 'text=/copied/i'
    - screenshot: dialog-after-copy
    - press: Escape
    - assert_not_visible: '[role="dialog"]'
```

Conventions:

- One `screenshot:` directive per meaningful visual state — not just the final state. The goal is to catch "the widget renders empty", "the button is clipped", "the modal is off-screen" — all invisible to a DOM assertion.
- Prefer role + accessible-name selectors over CSS classes. Class names drift; ARIA doesn't.
- Include at least one **edge state** per feature: empty list, very long content, mobile viewport (iPhone 13 size), dark-mode toggle if the app has one.
- For forms, include one valid submission and one validation-error submission.

Write all workflow blocks to `02_workflows.md`.

---

## Phase 3 — Visual sweep (delegate to qa-browser)

**Goal:** execute every workflow block in a real browser, capture evidence, and run visual-bug heuristics on every step.

Delegate to the `qa-browser` agent using the `Agent` tool. The prompt must contain:

1. The dev server URL (from Phase 1 preconditions).
2. Auth setup instructions (token to paste into localStorage, header to set, etc.).
3. The full contents of `02_workflows.md`.
4. The **visual-bug heuristic checklist** (below) — to be run on every step via `browser_evaluate`.
5. The exact artifact paths where screenshots and `03_observations.jsonl` must be written.

### Visual-bug heuristic checklist

After every `screenshot:` directive, the agent MUST run this script via `browser_evaluate` and record the result as one JSON line in `03_observations.jsonl`:

```js
(() => {
  const findings = [];
  const vw = window.innerWidth, vh = window.innerHeight;

  // 1. Empty containers that should have content
  document.querySelectorAll('[data-testid], main, section, article, [role="list"], [role="table"], tbody')
    .forEach(el => {
      const r = el.getBoundingClientRect();
      if (r.width > 50 && r.height > 50 && !el.textContent.trim() && el.children.length === 0) {
        findings.push({ kind: 'empty_container', selector: cssPath(el), size: [r.width, r.height] });
      }
    });

  // 2. Broken images
  document.querySelectorAll('img').forEach(img => {
    if (img.complete && img.naturalWidth === 0) {
      findings.push({ kind: 'broken_image', src: img.src, selector: cssPath(img) });
    }
  });

  // 3. Elements clipped off-viewport
  document.querySelectorAll('button, [role="button"], a, input, [role="dialog"]').forEach(el => {
    const r = el.getBoundingClientRect();
    if (r.width > 0 && r.height > 0 && (r.right < 0 || r.bottom < 0 || r.left > vw || r.top > vh)) {
      findings.push({ kind: 'offscreen_interactive', selector: cssPath(el), rect: [r.left, r.top, r.right, r.bottom] });
    }
  });

  // 4. Overlapping interactive elements (same center point, both clickable)
  // Sampled — full N^2 is too slow.
  const interactives = [...document.querySelectorAll('button, a, input, [role="button"]')].slice(0, 200);
  for (let i = 0; i < interactives.length; i++) {
    for (let j = i + 1; j < interactives.length; j++) {
      const a = interactives[i].getBoundingClientRect();
      const b = interactives[j].getBoundingClientRect();
      if (a.width && b.width && Math.abs((a.left+a.right)/2 - (b.left+b.right)/2) < 4
          && Math.abs((a.top+a.bottom)/2 - (b.top+b.bottom)/2) < 4) {
        findings.push({ kind: 'overlapping_interactive',
                        selectors: [cssPath(interactives[i]), cssPath(interactives[j])] });
      }
    }
  }

  // 5. Unstyled / FOUC regions — text nodes with default serif in a non-serif app
  // (Heuristic: app's <body> computed font-family should not be 'Times' etc. at observation time.)
  const bodyFont = getComputedStyle(document.body).fontFamily.toLowerCase();
  if (bodyFont.includes('times') || bodyFont.includes('serif') && !bodyFont.includes('sans')) {
    findings.push({ kind: 'possible_fouc', bodyFont });
  }

  // 6. Console errors captured by a wrapper installed on page load (see below)
  findings.push(...(window.__preflightConsoleErrors || []).map(e => ({ kind: 'console_error', message: e })));

  // 7. Network failures captured by the same wrapper
  findings.push(...(window.__preflightNetworkErrors || []).map(n => ({ kind: 'network_error', ...n })));

  function cssPath(el) {
    if (!(el instanceof Element)) return '';
    const parts = [];
    while (el && el.nodeType === 1 && parts.length < 6) {
      let sel = el.nodeName.toLowerCase();
      if (el.id) { sel += '#' + el.id; parts.unshift(sel); break; }
      const sib = el.parentNode ? [...el.parentNode.children].filter(c => c.nodeName === el.nodeName) : [];
      if (sib.length > 1) sel += `:nth-of-type(${sib.indexOf(el) + 1})`;
      parts.unshift(sel);
      el = el.parentElement;
    }
    return parts.join(' > ');
  }

  return findings;
})()
```

The wrappers `window.__preflightConsoleErrors` and `window.__preflightNetworkErrors` must be installed once per page-load via an init script injected at Playwright context creation:

```js
window.__preflightConsoleErrors = [];
window.__preflightNetworkErrors = [];
const origError = console.error;
console.error = (...args) => { window.__preflightConsoleErrors.push(args.map(String).join(' ')); origError(...args); };
window.addEventListener('error', e => window.__preflightConsoleErrors.push(e.message));
window.addEventListener('unhandledrejection', e => window.__preflightConsoleErrors.push(String(e.reason)));
const origFetch = window.fetch;
window.fetch = async (...a) => {
  const r = await origFetch(...a);
  if (!r.ok) window.__preflightNetworkErrors.push({ url: a[0], status: r.status });
  return r;
};
```

### Observation record format

Each line of `03_observations.jsonl`:

```json
{"ts":"2026-04-24T12:34:56Z","feature_id":"nodes-rotate-token","variant":"populated","step":"dialog-open","url":"/nodes","screenshot":"screenshots/nodes-rotate-token/004-dialog-open-populated.png","findings":[{"kind":"empty_container","selector":"main > div:nth-of-type(2)","size":[800,400]}]}
```

Every step is recorded — including ones with zero findings (so runs are diffable). The agent does not decide severity here; that happens in Phase 4.

---

## Phase 4 — Triage, repro, verdict

**Goal:** turn the observation stream into a short, actionable report a human can read in two minutes.

### Severity rules

| Severity | Triggers | Counts against verdict |
|---|---|---|
| **BLOCKER** | `console_error` with `TypeError` / `ReferenceError`, any 5xx network, empty-container on a core-feature page | Makes verdict BLOCKED |
| **BUG** | `broken_image`, `offscreen_interactive` on a clickable, 4xx (except 401/403 on auth-gated preview), `overlapping_interactive` on non-decorative elements | Makes verdict WARN if no BLOCKER |
| **WARN** | `possible_fouc`, `empty_container` on a non-core page, `console_error` that looks like a third-party warning (prefix `[vite]`, `[HMR]`, `Extension context invalidated`) | Stays WARN |
| **INFO** | 401/403 on an auth-gated page visited without the right token, a11y contrast findings | Does not affect verdict |

### Reproduction

For every BLOCKER and BUG, re-invoke `qa-browser` with a **minimal repro script**: navigate to the offending URL, replay only the click path that led to the finding, take `before.png`, trigger the action, take `after.png`. Save under `screenshots/bugs/<bug-id>/` with a `repro.md` that has:

- Exact URL
- Auth state (token name, not the value)
- Click path (4–6 steps)
- Expected vs observed (one line each)
- Console + network trace for just that interaction
- Likely culprit file (best-guess from stack trace + recent `git log --oneline -n 20`)

### Final verdict

Write `05_verdict.json`:

```json
{
  "status": "BLOCKED",
  "commit": "e3c8a62",
  "scope": null,
  "counts": { "blocker": 2, "bug": 5, "warn": 3, "info": 4, "features_tested": 27, "steps_executed": 184, "screenshots": 184 },
  "run_dir": "qa-runs/20260424T123456Z"
}
```

Write `04_bug_report.md` for humans. Structure:

```markdown
# Preflight verdict: BLOCKED

Run: `qa-runs/20260424T123456Z` · commit `e3c8a62` · scope: all
2 blockers · 5 bugs · 3 warnings · 27 features · 184 steps

## Blockers (fix before promoting)

### B1 · Sessions page crashes on empty list
- URL: `/admin/sessions` when no sessions recorded
- Evidence: `console_error` `TypeError: Cannot read properties of undefined (reading 'length')`
- Repro: screenshots/bugs/B1/
- Likely: `dashboard/src/pages/Sessions.tsx` — check the empty-data branch
- …

## Bugs

…

## Warnings

…

## Passed features

<details><summary>22 features passed cleanly</summary>
…
</details>
```

Only emit the verdict to the user once all four phases have written their files. Return:

- Verdict status (READY / WARN / BLOCKED)
- Counts
- Path to `04_bug_report.md`
- Path to the top 3 most severe bug folders

---

## Arguments

- `--scope <area>` — substring match on feature id / surface / source path. Narrows Phase 1 output.
- `--url <override>` — use this URL instead of probing the documented port. Useful for staging.
- `--no-launch` — never prompt to start the dev server; fail if not already running.
- `--base-run <path>` — compare this run's observations to a prior run's `03_observations.jsonl` and flag only *new* findings (regression-gating mode). Useful for "did this branch add new visual bugs vs main?"

---

## Output contract

When finished, respond in at most this shape:

```
preflight: <STATUS>
  blockers: N
  bugs: N
  warnings: N
  run: qa-runs/<timestamp>/
  report: qa-runs/<timestamp>/04_bug_report.md
```

Plus a 3-line summary of the top blocker if any. **Do not** dump the whole bug report inline — that's what the file is for. The user reads the file.

---

## Non-goals

- This skill does not fix bugs. It finds them. Fixing is a separate `/ship` cycle per bug.
- This skill does not replace unit / integration / e2e test suites. It is additive — a visual, user-POV layer on top of them.
- This skill does not enforce performance budgets. That belongs in a separate Lighthouse-style pass.
