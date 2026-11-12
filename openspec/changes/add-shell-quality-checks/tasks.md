# Tasks

## 1. Checker configuration and Makefile

- [ ] 1.1 Add `.editorconfig` per design D4:
  - `root = true` and LF line endings
  - shfmt sections, each with 2-space indent and `switch_case_indent = true`: `[{libexec/*,.githooks/*,scripts/*,spec/spec_helper.sh,spec/support/*.sh}]` and `[*.zsh]`
  - `shell_variant = zsh` for `*.zsh`
  - whitespace-only rules for `spec/**/*_spec.sh`

  Verify: `shfmt -l libexec zsh-claude-env.plugin.zsh` lists the same 8 files the design baseline predicts. No flags may be passed, so shfmt has to pick the style up from EditorConfig.
- [ ] 1.2 Add `.shellcheckrc` with `external-sources=true` and `source-path=SCRIPTDIR`, and no global `disable=`. Verify: `cd /tmp && shellcheck -x -a <repo>/libexec/ccenv-profile` resolves `ccenv--resolve.sh`, with no SC1091 "not following" message.
- [ ] 1.3 Write the `Makefile`, compatible with GNU make 3.81:
  - the `BASH_SRCS`, `ZSH_SRCS`, `TOOL_SRCS`, `SPEC_HELPERS`, and `SPEC_FILES` variables per D2. Use `$(wildcard)`, so entries for files that do not exist yet drop out.
  - targets `syntax`, `lint`, `fmt-check`, `fmt`, `test`, `spec-coverage`, `check` (the default goal), `install-hooks`, `versions`, and `help`
  - flags exactly as in the D3 table
  - every target `.PHONY`
  - a "why" comment on each block, matching the repo style

  Verify: `make help` lists every target, and `/usr/bin/make -n check` parses without error.
- [ ] 1.4 Add a tool guard (a macro or a `need-%` helper target). Every target fails with `missing required tool: <name>` when one of the tools it needs (`bash`, `zsh`, `shellcheck`, `shfmt`, `shellspec`) is missing. Verify: `PATH=/usr/bin:/bin make fmt-check` exits non-zero and names `shfmt`.
- [ ] 1.5 Confirm `make syntax` passes on the current tree. Then confirm it fails and names the file on a scratch copy with an injected unterminated `if`. Do not commit the broken copy.

## 2. ShellSpec suite (baseline = `openspec/specs/`)

- [ ] 2.1 Install ShellSpec (`brew install shellspec`, expected 0.28.1), and add its version to the `make versions` output. Verify: `shellspec --version` prints 0.28.1.
- [ ] 2.2 Add `.shellspec` (`--require spec_helper`, `--format documentation`), plus `spec/spec_helper.sh` and `spec/support/fixtures.sh`:
  - write both helpers in POSIX sh with `# shellcheck shell=sh`
  - add a hermetic `BeforeEach` per D8
  - add fixture helpers to create a registered profile, write `.claude-profile`, and write the global `$CCENV_ROOT/profile`

  Verify:
  - a temporary example asserting that `$HOME` lies under `$SHELLSPEC_TMPBASE` passes under both `--shell bash` and `--shell zsh`. Remove it afterward.
  - `make lint` and `make fmt-check` pass on the helpers
- [ ] 2.3 Write `scripts/spec-coverage` per D11 and wire it into `make spec-coverage` and `make check`. Verify:
  - with no spec files yet, it exits 1 and lists all 47 triples
  - with a scenario heading renamed in a scratch copy of `openspec/specs`, it names that triple
  - it passes `make lint` and `make fmt-check`
- [ ] 2.4 Write `spec/ccenv/ccenv_profiles_spec.sh`, which covers 5 requirements and 10 scenarios: register an existing environment, bootstrap new, bulk-register (`--discover`), remove, and list. Verify: `shellspec --shell bash spec/ccenv/ccenv_profiles_spec.sh` passes with zero failures, and `make spec-coverage` no longer lists any `ccenv-profiles` triple.
- [ ] 2.5 Write `spec/ccenv/ccenv_resolution_spec.sh`, which covers 7 requirements and 15 scenarios. The precedence tiers and the global/local/shell get-set scenarios run the CLI as a subprocess. The export and after-switch hook scenarios use the child-shell technique from D8 (`eval "$(ccenv init - zsh)"` inside `zsh -f -c`). Verify: the file passes under `--shell bash`, and no `ccenv-resolution` triples remain uncovered.
- [ ] 2.6 Write `spec/ccenv/ccenv_shell_integration_spec.sh`, which covers 4 requirements and 8 scenarios: init output for bash and zsh, the unsupported-shell error, immediate shell- and local-level effect, `ccenv with`, and the `cenv`/`ccv` aliases matching `ccenv` for a read-only command and a state-mutating command. Verify: the file passes, and its triples are covered.
- [ ] 2.7 Write `spec/plugin/extension_hooks_spec.sh`, which covers 4 requirements and 10 scenarios: `_claude_env_name` state, the baseline label at load, the after-switch hook point (including "ccenv not installed"), and git-context hook succeed/decline/undefined. Use `Include` on the plugin under zsh. Verify: `shellspec --shell zsh spec/plugin/extension_hooks_spec.sh` passes, and its triples are covered.
- [ ] 2.8 Write `spec/plugin/terminal_title_spec.sh`, which covers 4 requirements and 8 scenarios: title content with exact OSC 0 bytes, `zsh` vs. first-word job segment, `CLAUDE_ENV_TITLE_HOOKS` disabled before and after load, and `GHOSTTY_SHELL_FEATURES` deference. Use a throwaway `git init` repo for the repo/branch segments. Verify: the file passes under zsh, and its triples are covered.
- [ ] 2.9 Apply the divergence policy (D12). For every example that fails because the code does not match its baseline scenario:
  - add `Pending '<reason>'` as the example's first line, keeping its assertions intact
  - append a "Divergences found" list to the end of this tasks.md, giving the capability › requirement › scenario and the observed behavior for each

  Verify: `make test` exits 0, pending examples appear in its output, and the count of `Pending` lines in `spec/` equals the length of the divergence list. If there are none, the list says "None".
- [ ] 2.10 Confirm the full suite is wired and isolated. Verify:
  - `make test` runs both the bash and zsh passes and exits 0
  - `make spec-coverage` exits 0
  - `ls -la ~/.ccenv` and `ls -d ~/.claude*` output is identical before and after `make test`

## 3. Baseline cleanup (gate goes green)

- [ ] 3.1 Run `make fmt` and review the diff. It should be whitespace and layout only: `case`-arm indentation, `{` grouping, and `((` spacing in the plugin. Verify:
  - `make fmt-check` exits 0
  - `git diff -w --stat` shows only layout changes
  - `make test` still passes
- [ ] 3.2 Commit the reformat on its own ("style: apply shfmt baseline"), after the user approves the commit. Then add its SHA to a new `.git-blame-ignore-revs`. Verify: `git blame --ignore-revs-file .git-blame-ignore-revs libexec/ccenv-init` attributes reformatted lines to their earlier commits.
- [ ] 3.3 Add `# shellcheck shell=bash` to the top of `libexec/ccenv--resolve.sh`, below its header comment block. Verify: SC2148 is gone from `make lint` output.
- [ ] 3.4 Fix both SC2155 findings by splitting the declaration from the assignment: `ccenv` `abs_dirname`'s `local cwd`, and `ccenv-init` line ~64. Verify: SC2155 is gone, and `make test` still passes with the same pending set as task 2.9.
- [ ] 3.5 Add inline suppressions for SC2034 (resolver outputs), SC2088 (literal display tilde), and SC2016 (eval-emitted code). Each gets a one-line reason comment on the line above, per D5. Verify:
  - `make lint` exits 0 with no output
  - `grep -n 'shellcheck disable' libexec/*` shows only these codes, with no file-wide disables
  - `make check` exits 0

## 4. Pre-commit hook

- [ ] 4.1 Write `.githooks/pre-commit` in bash per D6, with mode 100755 via `git update-index --chmod=+x`. It must:
  - filter on the gate paths, including `spec/`, `.shellspec`, `scripts/`, and `openspec/specs/`
  - snapshot the index with `git checkout-index -a --prefix`, cleaned up by an `EXIT` trap
  - run `make -C "$tmp" check`
  - print a remediation hint on failure

  Verify: it passes `make lint` and `make fmt-check`, since it is in `TOOL_SRCS`.
- [ ] 4.2 Add the `install-hooks` target per D7. It sets `core.hooksPath=.githooks`, is idempotent, and warns if `.git/hooks/pre-commit` exists. Verify: run it twice. `git config --local core.hooksPath` prints `.githooks`, and the second run prints no error.
- [ ] 4.3 Exercise the spec scenarios in a throwaway clone (`git clone . "$scratch/hooktest"`). Verify each outcome:
  - staged lint error + unstaged fix → commit rejected
  - clean staged + unstaged syntax error → commit succeeds
  - a commit touching only `README.md` → the hook exits 0 instantly without running make
  - a staged rename of a scenario heading in `openspec/specs/` with no matching example → commit rejected by spec-coverage
  - after any of these runs, `git status` shows that the working tree and index are unchanged by the hook

## 5. Agent and contributor documentation

- [ ] 5.1 Rewrite CLAUDE.md "Development workflow" per D10:
  - a command table (`make check` / `fmt` / `lint` / `test` / `spec-coverage` / `install-hooks` / `versions`)
  - rules: run `make check` before claiming completion and report the result; use `make fmt`, not hand-formatting; never `--no-verify`; give every `# shellcheck disable=` a reason comment
  - spec-to-test rules: a scenario change in `openspec/specs/` ships with its matching `It` example; a divergent baseline example gets `Pending` with a reason, never deletion
  - the ShellSpec layout and naming convention
  - the zsh caveat: no ShellCheck coverage for the plugin
  - the tested tool versions
  - remove the "There is no build/lint/test tooling" sentence

  Verify: `grep -n 'no build/lint/test' CLAUDE.md` returns nothing, and every command in the new table runs successfully.
- [ ] 5.2 Add a short "Development" section to README.md: prerequisites (bash, zsh, shellcheck, shfmt, shellspec), `make install-hooks`, `make check`, and `make fmt`. Verify: the commands run as written on a fresh clone.

## 6. GitHub Actions (optional)

- [ ] 6.1 Add `.github/workflows/check.yml` per D9:
  - `push` and `pull_request` triggers
  - apt `zsh`
  - ShellCheck 0.11.0, shfmt 3.14.1, and ShellSpec 0.28.1 downloaded by exact release URL, with SHA-256 verification
  - `make check`

  Verify: `actionlint` passes if installed (otherwise review by hand), and after the user approves a push, the workflow run is green on GitHub, with pending examples reported and not failing.
- [ ] 6.2 Confirm CI catches what the hook catches. On a throwaway branch, push a commit made with `--no-verify` that contains a ShellCheck finding, then delete the branch. This requires the user's explicit approval to push. Verify: the workflow run fails on the lint step.

## 7. Integration check

- [ ] 7.1 From a fresh clone, run `make install-hooks && make check`. It exits 0. Then make one real commit through the hook (after the user approves the commit), and run `openspec validate add-shell-quality-checks --strict`. Verify: all three succeed.
