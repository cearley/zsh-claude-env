# Proposal

## Why

This repo has ~1,100 lines of bash (`libexec/ccenv*`) and a zsh plugin, and no automated checks. CLAUDE.md says "There is no build/lint/test tooling", so neither people nor agents get a consistent signal before committing. Running ShellCheck and shfmt against the tree today shows real findings: SC2155 masked return values, SC2088 tilde-in-quotes, a sourced file with no declared shell (SC2148), and 7 of 13 scripts that do not match a single format. The shell-tips guide (https://www.shell-tips.com/bash/syntax-check-test-lint-format) describes a four-step routine for this: `bash -n`, `shellcheck -x -a`, `shfmt -d`, and a test runner. This change uses ShellSpec as the test runner instead of the guide's Bats, because ShellSpec runs natively under zsh as well as bash. bash, shellcheck, and shfmt are already installed locally, so the routine can be adopted now at little cost.

## What Changes

- Add a **Makefile** as the single entry point for every check: `syntax`, `lint`, `fmt-check`, `fmt` (rewrite), `test`, and an aggregate `check`. It also adds `install-hooks`, plus a tool-presence check that names any missing binary.
- Add a **tracked git pre-commit hook** (`.githooks/pre-commit`), installed with `make install-hooks`. The hook runs `make check` against the *staged* snapshot of the repo, not the working tree, and blocks the commit on any failure.
- Add **checker configuration** so editors, the hook, CI, and agents all use the same settings:
  - `.editorconfig`: shfmt style, 2-space indent and indented `case` arms
  - `.shellcheckrc`: follow `source` and resolve paths relative to the script
- Add a **ShellSpec test suite** under `spec/` that uses the behaviors already in `openspec/specs/` as its baseline. There is one spec file per capability (`ccenv-profiles`, `ccenv-resolution`, `ccenv-shell-integration`, `extension-hooks`, `terminal-title`). Each requirement becomes a `Describe` block, and each scenario becomes an `It` example named after it word for word, which covers 21 requirements and 47 scenarios today. ccenv specs run under bash, and plugin specs run under zsh.
- Add a **spec-coverage check**, part of `make check`, that fails when any scenario in `openspec/specs/` has no matching example. Behavior specs and tests then cannot drift apart. If the current code diverges from a baseline scenario, its example is marked `Pending` with a reason, and the fix is left to a separate change.
- Make a **one-time baseline cleanup**: reformat the scripts with shfmt, and fix or explicitly annotate every current ShellCheck finding. The tree then passes `make check` from the first commit, so the gate starts green.
- Add an optional **GitHub Actions workflow** that runs `make check` on push and pull request, with pinned tool versions.
- Add **agent instructions**: rewrite CLAUDE.md's "Development workflow" section so agents run `make check` before claiming completion, use `make fmt` instead of hand-formatting, never bypass the hook with `--no-verify`, and justify any `# shellcheck disable=` inline. Add a short Development section to README.md for humans.

No runtime behavior of `ccenv` or the plugin changes. The baseline cleanup must preserve behavior; it is formatting and lint hygiene only.

## Capabilities

### New Capabilities
- `shell-quality-checks`: The repo's developer quality gate. It covers which shell sources are checked and with which tools, how tests trace back to the behavior specs, the Makefile targets and their exit-status contract, the pre-commit hook's staged-snapshot behavior, CI parity, and the instructions agents follow to use these tools.

### Modified Capabilities
None. The existing capabilities (`ccenv-profiles`, `ccenv-resolution`, `ccenv-shell-integration`, `extension-hooks`, `terminal-title`) describe runtime behavior, and this change does not alter any of their requirements.

## Impact

- **New files:**
  - `Makefile`
  - `.githooks/pre-commit`
  - `.editorconfig`
  - `.shellcheckrc`
  - `.shellspec`, `spec/spec_helper.sh`, `spec/{ccenv,plugin}/*_spec.sh`
  - `scripts/spec-coverage`, the coverage checker
  - `.github/workflows/check.yml`
- **Modified files:**
  - every `libexec/*` script: whitespace and format only, plus targeted lint fixes or annotated suppressions
  - `zsh-claude-env.plugin.zsh`: format only
  - `CLAUDE.md`: the Development workflow section is rewritten and the "no tooling" statement removed
  - `README.md`: a Development section is added
- **Developer dependencies:**
  - bash, shellcheck, and shfmt, which are assumed installed
  - ShellSpec, which is needed for `make test` and is **not yet installed** (`brew install shellspec`; 0.28.1 is the current stable release)
  - zsh, which is also needed for `make test` and is present on this machine
  - GNU make 3.81, the macOS system make. The Makefile must not rely on newer make features.
- **Git config:** `make install-hooks` sets the repo-local `core.hooksPath=.githooks`. Any hooks in `.git/hooks/` stop running for this repo; none exist today.
- **Contributors:** commits that fail the checks are rejected locally. `git commit --no-verify` remains a deliberate human escape hatch.
