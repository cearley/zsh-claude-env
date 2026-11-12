# Spec Delta

## Purpose

Defines the repo's developer quality gate. It covers which shell sources are syntax-checked, linted, format-checked, and tested; how those checks are run by people, git hooks, CI, and agents; and how they report failure.

## ADDED Requirements

### Requirement: Checked source set
The checks SHALL cover these kinds of source:
- every tracked bash source under `libexec/`, including sourced helpers that have no shebang
- the zsh plugin file
- the repo's own tooling scripts: the pre-commit hook and the coverage checker
- the test suite: ShellSpec spec files and their plain-shell helpers

The checks SHALL NOT cover the `bin/` symlinks or any untracked or ignored files. The Makefile SHALL declare the source set in one place.

#### Scenario: New libexec script is picked up
- **WHEN** a new `libexec/ccenv-<name>` bash script is added and `make check` runs
- **THEN** the script is syntax-checked, linted, and format-checked without any edit to the Makefile

#### Scenario: Ignored state directories are not scanned
- **WHEN** `profiles/`, `profile`, or `homes/` exist under the repo root
- **THEN** no check reads or reports on files inside them

### Requirement: Syntax check
`make syntax` SHALL parse each bash source with `bash -n`, the zsh plugin with `zsh -n`, and the ShellSpec spec files with ShellSpec's own syntax check, without executing any of them. It SHALL exit non-zero if any file fails to parse, and SHALL name each failing file.

#### Scenario: Unterminated construct
- **WHEN** a libexec script contains an unterminated `if` and `make syntax` runs
- **THEN** the target exits non-zero and the output names that script and line

### Requirement: Lint
`make lint` SHALL run ShellCheck on every bash source. ShellCheck SHALL follow sourced files and report findings inside them. Any finding at any severity SHALL make the target exit non-zero. The zsh plugin and the ShellSpec DSL spec files (`*_spec.sh`) SHALL be excluded from ShellCheck: ShellCheck does not support zsh, and it misreads the DSL. ShellSpec's plain-shell helper files SHALL be linted.

#### Scenario: Finding in a sourced helper
- **WHEN** `libexec/ccenv--resolve.sh` contains a ShellCheck finding and `make lint` runs
- **THEN** the finding is reported and the target exits non-zero

#### Scenario: Justified suppression
- **WHEN** a line carries a `# shellcheck disable=SCxxxx` directive
- **THEN** `make lint` does not report that code on that line

### Requirement: Format check and rewrite
`make fmt-check` SHALL report a diff for every source, bash and zsh, that does not match the repo's declared shfmt style. ShellSpec DSL spec files are excluded, because shfmt flattens their block indentation. The target SHALL exit non-zero when any diff exists. `make fmt` SHALL rewrite those files in place to the same style. A file rewritten by `make fmt` SHALL then pass `make fmt-check`.

#### Scenario: Misformatted file
- **WHEN** a script uses 4-space indentation and `make fmt-check` runs
- **THEN** a unified diff is printed and the target exits non-zero, leaving the file unchanged

#### Scenario: Auto-fix round-trip
- **WHEN** `make fmt` runs and is followed by `make fmt-check`
- **THEN** `make fmt-check` exits 0

### Requirement: Declared formatting style
The shfmt style SHALL be declared in a tracked config file that editors also read, not only on the command line. Every invocation (Makefile, hook, CI) SHALL take its formatting style from that file.

#### Scenario: Editor and checker agree
- **WHEN** an EditorConfig-aware editor saves a libexec script
- **THEN** it uses the same indentation width that `make fmt-check` enforces

### Requirement: Tests
`make test` SHALL run the ShellSpec suite under `spec/`, running ccenv specs under bash and plugin specs under zsh. It SHALL exit non-zero on any failing example. Tests SHALL NOT read or modify the developer's real `~/.ccenv`, `~/.claude*`, or shell rc files.

#### Scenario: Isolated test environment
- **WHEN** `make test` runs on a machine with real ccenv profiles registered
- **THEN** every example uses a temporary `HOME` and `CCENV_ROOT`, and the real profiles are unchanged afterward

#### Scenario: Test failure
- **WHEN** a ShellSpec expectation fails
- **THEN** `make test` exits non-zero and names the failing example

#### Scenario: Plugin specs run under zsh
- **WHEN** `make test` runs the plugin specs
- **THEN** they execute in zsh with no user rc files loaded

### Requirement: Tests trace to baseline behavior specs
For every capability spec in `openspec/specs/<capability>/spec.md`, the suite SHALL have one spec file for that capability. In it, each requirement SHALL have a `Describe` block and each scenario an `It` example, with the requirement and scenario names copied word for word.

#### Scenario: Example per scenario
- **WHEN** `openspec/specs/ccenv-resolution/spec.md` has the scenario "Falls through to global" under the requirement "Shell, local, and global precedence tiers"
- **THEN** the ccenv-resolution spec file has an example with that name, inside a group with that requirement's name

#### Scenario: Same scenario name in two capabilities
- **WHEN** the scenario "Hook not defined" appears in both `ccenv-resolution` and `extension-hooks`
- **THEN** each capability's spec file needs its own matching example

### Requirement: Spec coverage check
`make spec-coverage` SHALL fail, and SHALL list every missing (capability, requirement, scenario) triple, when the test suite lacks an example for a scenario in `openspec/specs/`. It SHALL exit 0 when every scenario is covered. The check SHALL fail the same way when a spec file lacks a matching requirement group, not only a matching example.

#### Scenario: New scenario without a test
- **WHEN** a scenario is added to a main spec and no matching example exists
- **THEN** `make spec-coverage` exits non-zero and names the capability, requirement, and scenario

#### Scenario: Renamed scenario
- **WHEN** a scenario heading is renamed in a main spec but its example keeps the old name
- **THEN** `make spec-coverage` exits non-zero

### Requirement: Divergence from a baseline behavior is explicit
When the current code does not exhibit a behavior that a baseline scenario specifies, the matching example SHALL be marked pending with a one-line reason. It SHALL NOT be deleted, skipped silently, or rewritten to match the code. Pending examples SHALL count as covered for `make spec-coverage`. ShellSpec SHALL report pending examples in its output.

#### Scenario: Code diverges from spec
- **WHEN** an example for a baseline scenario fails because ccenv behaves differently from the spec
- **THEN** the example is marked pending with a reason, `make test` still passes, and the test output lists the example as pending

### Requirement: Aggregate check
`make check` SHALL run syntax, lint, fmt-check, test, and spec-coverage. It SHALL exit 0 only when all five pass. `make` with no target SHALL behave as `make check`.

#### Scenario: Clean tree
- **WHEN** the committed tree is run through `make check`
- **THEN** it exits 0

#### Scenario: One stage fails
- **WHEN** only the format check fails
- **THEN** `make check` exits non-zero

### Requirement: Missing tool reporting
When a required tool (`bash`, `zsh`, `shellcheck`, `shfmt`, `shellspec`) is not on `PATH`, any target that needs it SHALL fail with a message naming the missing tool. It SHALL NOT silently skip the check.

#### Scenario: shfmt absent
- **WHEN** `shfmt` is not installed and `make fmt-check` runs
- **THEN** the target exits non-zero with a message naming `shfmt`

### Requirement: Pre-commit hook gates on staged content
A tracked pre-commit hook SHALL run `make check` against the content staged for commit, not the working tree. It SHALL block the commit when the checks fail. Unstaged edits SHALL NOT affect the hook's outcome, and the hook SHALL NOT modify the working tree or the index.

#### Scenario: Unstaged fix does not mask a staged error
- **WHEN** a staged version of a script fails lint but the unstaged working copy is fixed
- **THEN** the commit is rejected

#### Scenario: Unstaged breakage does not block a clean commit
- **WHEN** the staged content passes all checks but an unstaged edit introduces a syntax error
- **THEN** the commit succeeds

#### Scenario: Unrelated commit is not slowed down
- **WHEN** a commit stages only files outside the checked source set, the tests, the checker configuration, and `openspec/specs/` (for example, only `README.md` or files under `openspec/changes/`)
- **THEN** the hook exits 0 without running the checks

### Requirement: Hook installation
`make install-hooks` SHALL configure the repository, and only this repository, to use the tracked hook directory. It SHALL be idempotent.

#### Scenario: Fresh clone
- **WHEN** a contributor clones the repo and runs `make install-hooks`
- **THEN** the next `git commit` runs the tracked pre-commit hook

### Requirement: CI parity
A CI workflow SHALL run `make check` on every push and pull request. It SHALL use pinned versions of ShellCheck, shfmt, and ShellSpec, so that CI and local runs enforce the same rules.

#### Scenario: Pull request with a lint finding
- **WHEN** a pull request introduces a ShellCheck finding
- **THEN** the CI check fails

### Requirement: Agent workflow instructions
The repo's agent instructions SHALL direct agents to do the following:
- run `make check` and see it pass before reporting shell changes complete
- use `make fmt` instead of hand-formatting
- never bypass the hook with `--no-verify`
- put a reason comment next to any new ShellCheck suppression

#### Scenario: Agent finishes a libexec edit
- **WHEN** an agent following the repo's instructions edits a libexec script
- **THEN** it runs `make check` and reports its result before claiming completion
