# Tasks

## 1. Verify specs against code

- [x] 1.1 Re-read `zsh-claude-env.plugin.zsh` line by line against all four spec deltas and confirm no requirement describes behavior the code does not actually have — verify: manual line-by-line diff, no code changes made
- [x] 1.2 Confirm each scenario is concrete enough to double as a manual test case (clear WHEN input, clear THEN observable output) — verify: read-through of all four spec files

## 2. Integration Verification

- [x] 2.1 Run `openspec validate --strict` against this change and confirm it passes with no warnings — verify: `openspec validate baseline-plugin-specs --strict` exits 0
