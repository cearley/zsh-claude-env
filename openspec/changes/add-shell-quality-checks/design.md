# Design

## Context

The repo is two independent pieces of shell (see proposal.md, Why). The baseline that shapes the approach was observed on 2026-11-12 with bash 5.3.20, ShellCheck 0.11.0, shfmt 3.14.1, and zsh on PATH, ShellSpec **not** installed (Homebrew offers 0.28.1), and macOS `/usr/bin/make`:

- **Sources.**
  - `libexec/` holds 13 tracked bash files.
  - 12 of them have `#!/usr/bin/env bash`.
  - `libexec/ccenv--resolve.sh` has no shebang. It is sourced by `ccenv-profile`, `-global`, `-local`, `-list`, and `-sh-shell`, each via `source "$bin_path/ccenv--resolve.sh"` plus a `# shellcheck source=ccenv--resolve.sh` directive.
  - `bin/*` are symlinks into `libexec/`.
  - `zsh-claude-env.plugin.zsh` is the only zsh source.
- **Syntax.** `bash -n` passes on every libexec file, and `zsh -n` passes on the plugin.
- **ShellCheck findings** (`shellcheck -x -a`):
  - SC2148: no shell declared in `ccenv--resolve.sh`
  - SC2034: `CCENV_RESOLVED_PROFILE`/`_TIER` look unused, but they are outputs that the sourcing scripts read
  - SC2155 ×2: `local x="$(...)"`, in `ccenv` and `ccenv-init`
  - SC2088 ×2: intentional literal `'~/.zshrc'` in the user-facing message in `ccenv-init`
  - SC2016 ×4: intentional single-quoted shell code emitted for `eval`, in `-global`, `-local`, `-init`, and `-sh-shell`
- **Formatting.** The files are already 2-space indented with no tabs, but the style is mixed. `case` arms are indented in some files and not in others, and some use `bash )` padding. With `-i 2 -ci`, 7 libexec files plus the plugin differ (~71 changed lines). With plain `-i 2`, 4 differ. The plugin already indents its `case` arms.
- **Behavior specs.** `openspec/specs/` holds 5 capabilities with 21 requirements and 47 scenarios. Two scenario names, "Hook not defined" and "No call on a directory change or a local/global write", each appear in two capabilities.
- **Tests and hooks.** No tests exist. There is no `.github/`. `core.hooksPath` is unset, and `.git/hooks/` holds only samples.
- **Docs.** CLAUDE.md states "There is no build/lint/test tooling".

## Goals / Non-Goals

**Goals:**
- One command (`make check`) that people, the hook, CI, and agents all run identically.
- The hook judges exactly what will be committed.
- The gate starts green: the baseline cleanup lands in the same change, so no allowlist or "existing violations" mode is needed.

**Non-Goals:**
- The `pre-commit` framework (Python), lefthook, or any other hook manager.
- Linting zsh semantics. No tool does this well, so zsh gets parse and format checks only.
- Edge-case tests beyond the baseline scenarios. The suite covers exactly what `openspec/specs/` specifies; more tests come with future spec changes.
- Fixing code that diverges from a baseline scenario. Such examples go `Pending` (D12), and the fix belongs to a separate change.
- Test coverage measurement (ShellSpec's kcov integration).
- Changing any runtime behavior of `ccenv` or the plugin.

## Decisions

### D1. The Makefile is the single source of truth; the hook and CI only call `make`
The hook and the workflow invoke `make check` and nothing else. Tool flags therefore live in exactly one place.
- *Alternative:* the hook calls the tools directly. Rejected: flags drift between the hook, CI, and docs.
- *Constraint:* macOS ships GNU make 3.81. Avoid `.RECIPEPREFIX`, `$(file ...)`, `--output-sync`, and `.ONESHELL`. Use plain recipes with `set -e`-style `&&` chains or one shell line per check.

### D2. Source discovery by glob, not `shfmt -f`
The Makefile declares the source set:
- `BASH_SRCS := $(wildcard libexec/*)`
- `ZSH_SRCS := zsh-claude-env.plugin.zsh`
- `TOOL_SRCS := .githooks/pre-commit scripts/spec-coverage`: the repo's own bash tooling
- `SPEC_HELPERS := spec/spec_helper.sh $(wildcard spec/support/*.sh)`: plain POSIX sh that is sourced under both bash and zsh
- `SPEC_FILES := $(wildcard spec/*/*_spec.sh)`: ShellSpec DSL

This set excludes `bin/`, because it holds only symlinks to libexec, and the ignored state dirs (`profiles/`, `homes/`). New `libexec/ccenv-*` files are picked up automatically.
- *Alternative:* `shfmt -f .` (shebang and extension sniffing). Rejected: it would walk into `homes/`, which can contain arbitrary user files, and it treats a missing shebang inconsistently.

### D3. Tool flags
| Stage | bash sources (`BASH_SRCS`, `TOOL_SRCS`) | zsh plugin | `SPEC_HELPERS` | `SPEC_FILES` |
|---|---|---|---|---|
| syntax | `bash -n FILE`, once per file | `zsh -n FILE` | `sh -n FILE` | `shellspec --syntax-check` |
| lint | `shellcheck -x -a` | skipped (ShellCheck has no zsh support) | `shellcheck` (via a `# shellcheck shell=sh` directive) | skipped (DSL) |
| fmt-check | `shfmt -d` | `shfmt -d` (zsh dialect via EditorConfig) | `shfmt -d` | skipped (verified: shfmt flattens `Describe`/`It` block indentation) |
| test | — | — | — | two runs: `shellspec --shell bash spec/ccenv` and `shellspec --shell zsh spec/plugin` |
| spec-coverage | — | — | — | `scripts/spec-coverage` (D11) |

- **Syntax runs once per file.** `bash -n` does not follow `source`, and it stops at the first error. Running it per file means every broken file gets named.
- **ShellCheck runs at the default severity** (`style`). The baseline cleanup makes that achievable, and a lower bar would just accumulate debt.
- **Format checks print a diff.** `-d` gives contributors a diff to read, not just a file list.

### D4. Formatting style lives in `.editorconfig`, not on the command line
shfmt reads EditorConfig when no printer flags are passed; this was verified in a scratch copy, including `[libexec/*]` for extensionless files and `shell_variant = zsh` for `*.zsh`. The style is:
- `indent_style = space`
- `indent_size = 2`
- `switch_case_indent = true`, i.e. `-ci`

This applies to `libexec/*`, `*.zsh`, `.githooks/*`, `scripts/*`, and `spec/spec_helper.sh` + `spec/support/*.sh`. `*_spec.sh` files get only basic EditorConfig whitespace rules. They are still indented by hand in the 2-space block style that ShellSpec's docs use.
- **Why `-ci`:** it matches the plugin and most of libexec. The extra reformat (7 files rather than 4) is a one-time cost.
- **Known cosmetic effect:** shfmt rewrites `(( $+functions[x] ))` to `(($+functions[x]))` in the plugin. This is accepted; it is semantically identical. CLAUDE.md's prose describing the convention can keep the spaced form.
- *Alternative:* flags in the Makefile only. Rejected: editors would not agree with the checker.

### D5. `.shellcheckrc` at the repo root
It sets:
- `external-sources=true`
- `source-path=SCRIPTDIR`

With these, `-x` resolves `ccenv--resolve.sh` regardless of the working directory, including inside the hook's temp snapshot (D6). `ccenv--resolve.sh` gets a `# shellcheck shell=bash` directive in place of a shebang, which keeps it non-executable-looking, as its header comment intends.

**Baseline finding policy:**
- **Fix:** SC2155. Split the declaration from the assignment; behavior is identical.
- **Suppress inline**, each with a one-line reason comment:
  - SC2034: the variables are outputs read by the sourcing scripts. Suppress at the assignment.
  - SC2088: the tilde is a deliberately literal display string.
  - SC2016: the single-quoted text is code emitted for `eval`.
- **No global `disable=`** in `.shellcheckrc`. Suppressions stay visible next to the code they excuse.

### D6. The pre-commit hook checks a snapshot of the index
`.githooks/pre-commit` (bash, itself linted and formatted) works in four steps:
1. **Skip unrelated commits.** List the staged paths with `git diff --cached --name-only --diff-filter=ACMR`. If none matches the gate paths, exit 0. The gate paths are `libexec/`, `bin/`, `*.zsh`, `spec/`, `.shellspec`, `scripts/`, `openspec/specs/`, `Makefile`, `.editorconfig`, `.shellcheckrc`, and `.githooks/`. `openspec/specs/` is included because editing a scenario can break spec coverage.
2. **Snapshot the index.** Create a temp dir with `mktemp -d`, and set an `EXIT` trap to remove it. Run `git checkout-index -a --prefix="$tmp/"`. This writes the complete staged tree (the Makefile, configs, libexec, specs, and `openspec/specs/`) without touching the working tree or the index.
3. **Run the checks.** `make -C "$tmp" check`. The exit status of `make` is the hook's exit status.
4. **On failure, explain the next step.** Print a hint: run `make fmt` / `make check`, re-stage, and commit again.

- *Alternative:* `git stash --keep-index`. Rejected: it mutates the working tree, it is fragile with partially staged files, and it has a long history of losing work when interrupted.
- *Alternative:* check the working-tree copies of the staged files. Rejected: it fails the "unstaged fix masks staged error" scenario in the spec.
- **Cost:** the repo is ~1.1k lines, so a full snapshot plus `make check` stays well under a few seconds. This is why the hook checks the whole tree rather than only the changed files. It also means a staged edit that breaks a file it sources is still caught.

### D7. Installation via `core.hooksPath`
`make install-hooks` runs `git config core.hooksPath .githooks`, which is repo-local and idempotent. It also `chmod +x`'s the hook. The hook script is executable in git (mode 100755), so a fresh clone needs only `make install-hooks`.
- *Alternative:* symlink into `.git/hooks/`. Rejected: it is per-clone state that is easy to forget, and `core.hooksPath` is the modern equivalent.

### D8. ShellSpec suite: layout, shells, and isolation
**Layout:**
```
.shellspec                      # --require spec_helper, --format documentation, --sandbox-off
spec/spec_helper.sh             # POSIX sh; hermetic env + shared fixtures
spec/support/fixtures.sh        # make_profile <name>, write_local, write_global, ...
spec/ccenv/ccenv_profiles_spec.sh
spec/ccenv/ccenv_resolution_spec.sh
spec/ccenv/ccenv_shell_integration_spec.sh
spec/plugin/extension_hooks_spec.sh
spec/plugin/terminal_title_spec.sh
```
- **Naming.** Each file is named after its capability, with `-` replaced by `_` so that ShellSpec discovers it.
- **Structure.** The top-level `Describe` is the capability id (e.g. `Describe 'ccenv-resolution'`). Nested inside are `Describe '<Requirement name>'` and `It '<Scenario name>'`, each copied word for word from the headings. This is the contract that D11 checks.
- **Why two directories and two runs.** ShellSpec executes a whole run under a single shell. The ccenv capabilities run under bash; the plugin capabilities run under zsh. This lets plugin examples `Include` the plugin and call its functions in the shell it actually targets.
- **Why ShellSpec rather than Bats** (Bats is the article's choice): ShellSpec runs natively under zsh, which suits a zsh plugin. Its `Describe`/`It` nesting also maps one-to-one onto requirement/scenario headings.

**Isolation.** A `BeforeEach` hook in `spec_helper.sh` does the following:
- sets `HOME` and `CCENV_ROOT` to fresh directories under `$SHELLSPEC_TMPBASE`
- unsets `CLAUDE_CONFIG_DIR`, `CCENV_PROFILE`, `CCENV_SHELL`, `CCENV_LOADED`, `CCENV_DEBUG`, and `GHOSTTY_SHELL_FEATURES`
- `cd`s into a temp working directory
- prepends `$SHELLSPEC_PROJECT_ROOT/libexec` to `PATH`

It runs before every example, so no example can touch the developer's real `~/.ccenv` or `~/.claude*`.

**Techniques by capability:**
- **ccenv-profiles, `ccenv-resolution` get/set:** run the real CLI as a subprocess, `When run command ccenv <sub> …`, then assert stdout, stderr, exit status, and the resulting files and symlinks under `$CCENV_ROOT`.
- **ccenv-resolution precedence, "Report the resolved profile":** subprocess `ccenv profile`, with fixture symlinks. `Include` of `libexec/ccenv--resolve.sh` is used only where a scenario names an internal tier that the CLI does not expose.
- **ccenv-shell-integration, the export/hook scenarios in ccenv-resolution:** run a child shell, `bash --norc --noprofile -c` or `zsh -f -c`, that does `eval "$(ccenv init - <shell>)"` and then performs the scenario's steps (`cd`, `ccenv shell x`, define `claude_env_after_switch`, …). The child echoes the observable state (`$CLAUDE_CONFIG_DIR`, a hook call counter) for the example to assert.
- **Persistence across shells** ("Override does not persist to a new shell"): a second, independent child shell that sources init freshly and reports its resolution.
- **terminal-title, extension-hooks:** `Include` the plugin under zsh, set variables, and call the precmd/preexec handlers and `_claude_env_name`/`_claude_env_git_context` directly. The OSC 0 escape is captured from stdout and compared byte for byte. Git scenarios use a throwaway `git init` repo in the example's temp dir.

### D9. CI runs on `ubuntu-latest` with pinned binaries
`.github/workflows/check.yml` triggers on `push` and `pull_request`. Its steps:
1. `actions/checkout` (pinned major).
2. `apt-get install zsh`.
3. Download ShellCheck 0.11.0, shfmt 3.14.1, and the ShellSpec 0.28.1 release tarball by exact URL, each verified with SHA-256.
4. `make check`.

- **Why not apt for ShellCheck and shfmt:** Ubuntu's apt versions lag (ShellCheck 0.9.x; shfmt predates zsh dialect support), so CI would disagree with local runs.
- **Pin ShellSpec too.** Use the release tarball, not the `curl | sh` installer, so the version is deterministic. Its version also needs to match local runs, because report formatting and the `Pending` semantics vary between releases.
- **This piece is optional.** Every other piece works without it, and its tasks are grouped separately.

### D10. Agent instructions live in CLAUDE.md's Development workflow
Replace the "no build/lint/test tooling" paragraph with a short command table (`make check`, `make fmt`, `make lint`, `make test`, `make spec-coverage`, `make install-hooks`, `make versions`) and rules that map one-to-one to the spec requirement "Agent workflow instructions". It also notes that ShellCheck does not cover the zsh plugin, so `zsh -n` plus manual sourcing remains the plugin's behavioral check. It also adds two spec-driven rules. First, a change to a main spec's scenarios ships with matching examples. Second, a failing baseline example is marked `Pending` with a reason, not deleted or bent to fit the code. README.md gets a brief Development section for humans.
- *Alternative:* a separate AGENTS.md. Rejected: CLAUDE.md is already this repo's agent-instruction file, and splitting would duplicate it.

### D11. Spec-coverage check
`scripts/spec-coverage` (bash, linted and formatted like libexec) builds two sets and diffs them:
- **Expected:** for each `openspec/specs/<cap>/spec.md`, the triple (`<cap>`, the text after `### Requirement: `, the text after `#### Scenario: `).
- **Actual:** for each `spec/*/<cap_with_underscores>_spec.sh`, the triples taken from the top-level `Describe`, the nested `Describe`, and the `It` strings. Single- and double-quoted forms are both accepted, and `Pending`/`Skip` lines inside an `It` do not affect matching.

The script prints each missing triple as `<cap> › <requirement> › <scenario>` and exits 1 if any are missing. Extra examples are allowed, because helper and edge-case examples may exist. It reads only headings, using `grep`/`sed` with no OpenSpec CLI dependency, so it runs identically in the hook snapshot and in CI.
- *Alternative:* `openspec show --json` to read the specs. Rejected: it would make the Node-based OpenSpec CLI a hard dependency of `make check` and CI.
- *Alternative:* `shellspec --list examples`. Rejected: it lists example IDs, not the nested description strings, so a regex over the spec files is simpler and more transparent.
- **Matching rules:** after trimming whitespace, the strings must match exactly. Case and punctuation both matter, so a heading edit forces a matching test edit, which is the point.

### D12. Divergence policy: `Pending` with a reason
If a baseline example fails because the code does not match the spec, the example keeps its spec-derived assertions and gets `Pending '<one-line reason>'` as its first line. ShellSpec still runs a pending example, reports it as pending, and does not fail the run. If the code later starts matching, ShellSpec flags the example ("fixed"), which prompts removing the marker.
- Each divergence is also recorded in the tasks.md report for this change, so it can become its own follow-up change.
- *Alternatives:* `Skip` and deleting the example. Both rejected: neither keeps the assertion live, so a fix would go unnoticed.

## Risks / Trade-offs

- **One-time reformat.** The reformat touches ~8 files, which adds `git blame` noise. → Land it as its own commit ("style: apply shfmt baseline"), and add that commit to `.git-blame-ignore-revs`.
- **Version skew.** A local tool upgrade (e.g. ShellCheck 0.12) adds new warnings that CI does not see, or the reverse. → CI pins versions. CLAUDE.md records the tested versions, and `make versions` prints the local ones for comparison.
- **The hook can be bypassed** with `--no-verify`. → CI is the backstop. Agent instructions forbid the bypass.
- **shfmt's zsh dialect is newer and less battle-tested** than its bash support, and could mis-parse future zsh constructs. → `zsh -n` remains the authoritative syntax check. If shfmt chokes on valid zsh, exclude the plugin from fmt-check rather than contort the code, and record that in the Makefile comment.
- **`core.hooksPath` shadows hooks.** Setting it means any future tool that installs into `.git/hooks/pre-commit` is silently ignored (for example, the specstory-guard skill). → The Makefile `install-hooks` target warns if `.git/hooks/pre-commit` exists. Additional hooks should be chained from `.githooks/pre-commit`.
- **Mistakes in the lint cleanup.** The cleanup edits real logic lines (SC2155 splits). → The ShellSpec suite lands *before* the cleanup (see Migration Plan) and acts as the regression net.
- **Some baseline scenarios are hard to automate.** Examples are "Override does not persist to a new shell", the `cd`-driven export, and terminal-managed titles. → D8's child-shell technique covers them. Anything that still cannot be observed non-interactively is marked `Pending` with a reason; it is never silently omitted.
- **Spec wording churn.** Any heading edit in `openspec/specs/` now requires a test edit. → This is intended. The coverage failure message names the exact triple to rename.
- **Bash/zsh portability of `spec_helper.sh`.** The helper is sourced under both shells. → Keep it POSIX sh, and lint it with `shell=sh`.
- **ShellSpec is not installed yet.** → The first task in the suite group installs it (`brew install shellspec`) and records the version. The Makefile tool guard names it if it is missing.

## Migration Plan

1. Land the configuration and the Makefile.
2. Land the ShellSpec suite and `spec-coverage`. Record any divergences as `Pending`.
3. Land the baseline cleanup: the reformat commit, then the lint commit. The suite guards behavior.
4. Land the hook and `install-hooks`.
5. Land the docs.
6. Land CI (optional).

Each step leaves the targets it touches green. `make check` as a whole is green from step 3 onward.

**Rollback:** `git config --unset core.hooksPath` disables the hook locally. Deleting the workflow file disables CI. None of this affects ccenv or plugin users.

## Open Questions

- Should CI also run on `macos-latest`, so that `/usr/bin/make` 3.81 and BSD userland are exercised? Deferrable. It would only add a matrix entry.
