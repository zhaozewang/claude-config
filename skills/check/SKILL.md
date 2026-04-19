---
name: check
description: Run all quality checks — lint, format, and tests — for the current Python project
argument-hint: /check
user-invocable: true
context: fork
---

# Run All Quality Checks

Run linting, format verification, and the full test suite for the current Python project.

## Steps

Run these three commands sequentially from the repo root. Report each result as it completes.

1. **Lint** — Run: `python3 -m ruff check .`
   - If there are violations, list them and suggest fixes.
   - If ruff is not installed, try `pip install ruff` first.

2. **Format check** — Run: `python3 -m ruff format --check .`
   - If files would be reformatted, list them. Offer to run `ruff format .` to fix.

3. **Tests** — Run: `python3 -m pytest tests/ -v`
   - If any tests fail, show the failure details and suggest a fix.

4. **Summary** — Report a final pass/fail status for each of the three checks.

## Notes

- The project's ruff config lives in `pyproject.toml` under `[tool.ruff]`.
- All three checks must pass for the codebase to be considered clean.
- If `pyproject.toml` specifies `src` layout, ruff and pytest will pick it up automatically.
