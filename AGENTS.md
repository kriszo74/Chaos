# Repository Guidelines

## Project Structure & Modules
- Root `.jl` scripts contain all source:
  - `main.jl` – entry point/runner.
  - `source.jl` – core logic/utilities.
  - `gui.jl` – UI-related routines (if used).
  - `3dtools.jl` – 3D/geometry helpers.
- Add tests under `test/` (e.g., `test/runtests.jl`, `test/test_core.jl`).
- Place any data/assets under `assets/` and reference with relative paths.

## Build, Run, and Test
- Run the program:
  - `julia main.jl`
  - From REPL: `include("main.jl")`
- Format code (recommended):
  - `julia -e 'using Pkg; Pkg.add("JuliaFormatter"); using JuliaFormatter; format(".")'`
- Run tests (when `test/` exists):
  - `julia test/runtests.jl`
  - Or REPL: `include("test/runtests.jl")`

## Coding Style & Naming
- Indentation: 4 spaces; UTF-8; max ~92 chars/line.
- Naming: `snake_case` for functions/variables; `CamelCase` for modules/types.
- Documentation: triple-quoted docstrings above public methods; include minimal examples.
- Patterns: avoid global mutation; prefer pure functions; use broadcasting and dot calls.
- Lint/format with `JuliaFormatter`; keep diffs minimal and focused.

## Testing Guidelines
- Framework: `Test` stdlib.
- Layout: `test/runtests.jl` includes other `test_*.jl` files.
- Conventions: one behavior per test block; use `@test`, `@test_throws`.
- Coverage: target meaningful coverage of new/changed code; add regression tests for bugs.

## Commit & Pull Requests
- Commits: imperative mood, concise scope (e.g., `fix: handle empty mesh`).
- Reference issues with `Fixes #123` when applicable.
- PRs must include:
  - Clear summary, context, and rationale.
  - Linked issues; screenshots/GIFs for UI changes (`gui.jl`).
  - Notes on tests added/updated and any breaking changes.

## Architecture Notes
- Keep `main.jl` thin: parse args/setup and delegate to `source.jl` APIs.
- Encapsulate UI-only logic in `gui.jl`; reuse core functions from `source.jl`.
- Isolate geometry/math in `3dtools.jl` with unit-tested, side-effect–free functions.

## Security & Configuration
- Do not commit secrets or machine-specific paths.
- Prefer environment variables or `config/*.toml` when configuration is needed.
