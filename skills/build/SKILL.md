---
name: build
description: Build the project and report any errors
argument-hint: /build
disable-model-invocation: true
context: fork
user-invocable: true
---

# Build Project

Build the project and report any errors.

## Steps

1. **Detect the build system** by checking the current working directory for:
   - `package.json` with a `build` script -> `npm run build`
   - `pyproject.toml` with `[build-system]` -> `python -m build` or the configured tool
   - `Makefile` with a `build` target -> `make build`
   - `Cargo.toml` -> `cargo build`
   - `go.mod` -> `go build ./...`

2. **Run the build command** detected above.

3. **If the build succeeds**, report success and note the output location.

4. **If the build fails**, analyze the error output:
   - **Type errors** (TypeScript/Go/Rust): List each error with file path, line number, and explanation.
   - **Import/module errors**: Check dependency installation and import paths.
   - **Missing dependencies**: Suggest installing them.

5. **For TypeScript projects**, optionally run `npx tsc --noEmit` for more detailed per-file diagnostics if the bundler output is unclear.
