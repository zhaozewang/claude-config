---
name: test
description: Run the test suite, optionally filtered by file or pattern
argument-hint: "[file-or-pattern]"
context: fork
user-invocable: true
---

# Run Tests

Run the project's test suite and report results.

If $ARGUMENTS is provided, use it as a filter (file path or pattern).

## Steps

1. **Detect the test runner** by reading `package.json` and `pyproject.toml` in the current working directory.

2. **Node.js projects** (package.json with a `test` script):
   ```bash
   npm test -- $ARGUMENTS
   ```
   If `$ARGUMENTS` is empty, run without the filter. Common runners: vitest, jest, mocha.

3. **Python projects** (pyproject.toml or pytest config):
   - With filter: `PYTHONPATH=src python -m pytest $ARGUMENTS -v --tb=short`
   - Without filter: `PYTHONPATH=src python -m pytest tests/ -v --tb=short`
   - If `ModuleNotFoundError`, check that `PYTHONPATH=src` is set or suggest `pip install -e ".[dev]"`.

4. **If no test runner is detected**, check for common setups and suggest installing one appropriate to the project.

5. **Report results**: total passed, failed, skipped. For failures show the test name, assertion, and likely cause.

## Options

- Add `--lf` (pytest) or `--reporter=verbose` (vitest) for detailed output.
- Add `-x` (pytest) or `--bail` (vitest/jest) to stop on first failure.
