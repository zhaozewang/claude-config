---
name: enforce-private-licensing
description: Audit and enforce proprietary licensing — run proactively after modifying config, CI, or dependency files
---

# Enforce Private Licensing

**All BPX code is proprietary. NEVER publish to public registries. NEVER use OSI-approved licenses.**

Run this audit after modifying pyproject.toml, package.json, CI workflows, Dockerfiles, or README files.

## Checks

### 1. License declarations

Verify `pyproject.toml` contains:
```toml
license = "LicenseRef-Proprietary"
```

If a `[project.classifiers]` section exists, it MUST include:
```
"License :: Other/Proprietary License"
```

And MUST NOT include any of:
```
"License :: OSI Approved :: MIT License"
"License :: OSI Approved :: Apache Software License"
"License :: OSI Approved :: BSD License"
"License :: OSI Approved"
```

For any `package.json` (e.g., `dashboard/package.json`), verify:
```json
"license": "UNLICENSED",
"private": true
```

### 2. No LICENSE files with OSI content

Check for `LICENSE`, `LICENSE.md`, `LICENSE.txt` in the repo root. If one exists, it must contain a proprietary notice like:
```
Copyright (c) 2024 BPX AI. All rights reserved.
This software is proprietary and confidential.
Unauthorized copying, distribution, or use is strictly prohibited.
```

It must NOT contain MIT, Apache, BSD, GPL, or any OSI license text.

### 3. No public registry publishing in CI

Scan `.github/workflows/*.yml` for:
- `twine upload` without `--repository-url` pointing to a private registry
- `npm publish` without `--registry` pointing to a private registry
- `pypa/gh-action-pypi-publish` (publishes to public PyPI)
- `docker push` to Docker Hub (hub.docker.com)
- Any reference to `upload.pypi.org`, `pypi.org/project/`, `registry.npmjs.org` as a publish target

These are ALL forbidden. Publishing is only allowed to:
- GitHub Packages (private, org-scoped)
- Private registries explicitly configured
- `git+https://github.com/bpx-ai/` install references (requires org access)

### 4. No open-source community files

These files imply open-source contribution and should NOT exist:
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `.github/FUNDING.yml`
- `.github/SECURITY.md` with public vulnerability disclosure

### 5. README checks

Verify README.md does NOT contain:
- `pip install bpx-sdk` (without `git+https://github.com/bpx-ai/` prefix)
- `npm install @bpx/runtime` (from public npm)
- "Open source", "open-source", "OSS" as project descriptors
- "Fork this repo" or "contributions welcome" language

### 6. No committed secrets

Verify `.env` files are in `.gitignore`:
```bash
git ls-files --cached | grep -E "\.env$" | grep -v ".env.example"
```
This must return empty. If any `.env` file is tracked, remove it from git immediately.

### 7. Docker image references

Dockerfiles must NOT push to public registries. Check for:
- `docker push` in any script or CI file
- References to `docker.io/` or `hub.docker.com` as push targets

## Remediation

If any check fails:
1. Fix the violation immediately
2. Log what was found: `logger.warning("Licensing violation found", file=path, issue=description)`
3. If a secret was committed to git history, alert the user — it requires `git filter-branch` or BFG to purge

## Execution

```bash
# Quick check script
echo "=== License fields ==="
grep -r "license" pyproject.toml 2>/dev/null
grep '"license"' package.json dashboard/package.json 2>/dev/null

echo "=== OSI license refs ==="
grep -rl '"MIT"\|"Apache"\|"BSD"\|"GPL"' pyproject.toml package.json 2>/dev/null

echo "=== Public publish in CI ==="
grep -rl "pypi.org\|npm publish\|docker push" .github/workflows/ 2>/dev/null

echo "=== Tracked .env files ==="
git ls-files --cached | grep -E '\.env$' | grep -v '.env.example'

echo "=== LICENSE file content ==="
head -5 LICENSE* 2>/dev/null

echo "=== Community files ==="
ls CONTRIBUTING.md CODE_OF_CONDUCT.md .github/FUNDING.yml .github/SECURITY.md 2>/dev/null
```

All checks must pass with no output (or only proprietary declarations).
