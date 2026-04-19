Launch the **manager** agent to execute the full closed-loop pipeline for the following request:

$ARGUMENTS

The manager agent will:
1. Read CLAUDE.md for project context
2. Spec the feature (pm-spec)
3. Design the solution (architect + domain specialists if available)
4. Implement it (domain-specialist or general implementer)
5. Build + lint + test (automated)
6. Simplify the code (automated code review)
7. Browser QA via Playwright (automated — verify in a real browser)
8. If anything fails in steps 4-7, loop: fix → re-test → re-QA (max 3 attempts)
9. Run eval if business logic changed
10. Run hygiene to update docs and memory
11. Report final results with evidence

**Do not ask the user for manual testing.** The pipeline has a browser. Use it.
**Do not report until everything passes** (or you've exhausted 3 retry attempts).
**Pass exact failure evidence** (DOM state, console errors, screenshots) between retry iterations.
