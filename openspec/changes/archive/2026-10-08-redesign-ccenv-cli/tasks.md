# Tasks

## 1. ccenv scaffold & profile management

- [x] 1.1 Create `bin/ccenv` -> `libexec/ccenv` dispatcher (command-name lookup, mirroring jenv's `libexec/jenv`), plus `bin/cenv` and `bin/ccv` as additional symlinks to the same dispatcher — verify: `bash -n`/`zsh -n` passes on all new scripts; `ccenv`, `cenv`, and `ccv` each print usage and exit non-zero with no args; `cenv list` and `ccv list` produce output identical to `ccenv list`
- [x] 1.2 Implement `ccenv add <name> <path>` — verify: against a scratch directory, confirm the symlink is created at `~/.ccenv/profiles/<name>`; confirm non-zero exit with no change for a nonexistent path and for an already-registered name, per `ccenv-profiles` scenarios
- [x] 1.3 Implement `ccenv add <name> --new` — verify: creates and registers an empty directory; confirm no `claude` process is ever started, per the bootstrap scenario
- [x] 1.4 Implement `ccenv add --discover` — verify: against scratch `~/.claude-*` directories (with and without `.claude.json`, some pre-registered), confirm register/skip outcomes match all three discovery scenarios
- [x] 1.5 Implement `ccenv remove <name>` — verify: removes the symlink only, leaves the real directory and its contents untouched; non-zero exit for an unknown name
- [x] 1.6 Implement `ccenv list` — verify: output matches the active-with-tier and empty-registry scenarios
- [x] 1.7 Document profile management (`add`, `remove`, `list`) in `README.md` — verify: every documented flag and example matches the actual implementation's behavior

## 2. Resolution engine

- [x] 2.1 Implement the shell>local>global precedence resolver as a shared internal function used by `profile`, `global`, `local`, and `shell` — verify: manual walk-through of all four precedence scenarios in `ccenv-resolution/spec.md` (shell wins, local found in an ancestor, falls through to global, nothing set)
- [x] 2.2 Implement `ccenv global [<name>|--unset]` — verify: get/set/unset match scenarios; setting an unregistered name leaves the global default unchanged and exits non-zero
- [x] 2.3 Implement `ccenv local [<name>|--unset]` — verify: writes/reads `.claude-profile` correctly; `--unset` removes only the current directory's file, leaving an ancestor's file untouched, per scenario
- [x] 2.4 Implement the `sh-shell` output half of `ccenv shell [<name>|--unset]` (prints the `export`/`unset` statement; live-shell wiring happens in task 3.1) — verify: `ccenv sh-shell <name>` and `ccenv sh-shell --unset` print the correct statement for a registered name, an unregistered name, and no argument
- [x] 2.5 Implement `ccenv profile` — verify: reports the resolved profile and its tier, or "none active," matching both scenarios
- [x] 2.6 Document the precedence model and each command in `README.md` — verify: README's precedence example matches the resolver's actual behavior

## 3. Shell integration

- [x] 3.1 Implement `ccenv init -` for bash and zsh: `PATH` prepend, the `ccenv()` eval-wrapper function for `shell`, and a `precmd` (zsh) / prompt-command (bash) hook registration — verify: `eval "$(ccenv init -)"` in a fresh bash session and a fresh zsh session each defines the wrapper function and activates the hook with no errors; an unsupported shell name reports unsupported and makes no changes
- [x] 3.2 Wire the hook to resolve and export `CLAUDE_CONFIG_DIR` every prompt — verify: `cd`-ing between two directories with different local profiles changes the exported value by the next prompt with no other command run, per the resolution scenario
- [x] 3.3 Invoke `claude_env_after_switch` on an explicit `ccenv shell` switch only — verify: define a test `claude_env_after_switch` that appends to a log file; confirm exactly one log line per `ccenv shell`/`ccenv shell --unset` call, and zero lines for `ccenv local`, `ccenv global`, or a `cd`-triggered resolved-profile change (none of those three notify)
- [x] 3.4 Implement `ccenv with <name> <cmd...>` — verify: runs `<cmd>` with `CLAUDE_CONFIG_DIR` set to `<name>`'s real directory; confirm the calling shell's own shell/local/global state is unchanged afterward; non-zero exit and `<cmd>` never started for an unregistered name
- [x] 3.5 Add a `CCENV_LOADED` marker set by `init -`, and a stderr warning from `shell`/`local`/`global` when it's absent — verify: running `ccenv shell <name>` in a shell that never eval'd `init -` prints the warning
- [x] 3.6 Document installation (`git clone`, `PATH` export, `eval "$(ccenv init -)"`) in `README.md`, mirroring jenv's install section — verify: following the documented steps in a brand-new shell results in a working `ccenv`
- [x] 3.7 Verify `cenv`/`ccv` match `ccenv` for a state-mutating command once shell integration is active — verify: with `eval "$(ccenv init -)"` loaded, `cenv shell work` and `ccv shell work` each change the current shell's resolved profile exactly as `ccenv shell work` would, per the alias scenario in `ccenv-shell-integration/spec.md`

## 4. Slim the existing plugin

- [x] 4.1 Remove the `~/.claude-*` discovery loop, the generated `claude-<name>` functions (and their character-set validation guard), and the `claude-env` function from `zsh-claude-env.plugin.zsh` — verify: `zsh -n` passes; `grep` confirms no references to any removed function remain in the file
- [x] 4.2 Update the plugin's header comments describing the after-switch hook to reflect that `ccenv`'s resolution step now triggers it, not the plugin itself — verify: comments accurately describe the new trigger; no behavioral code change needed here since the hook-invoking code lived entirely in the removed `claude-env` function
- [x] 4.3 Update `CLAUDE.md`'s architecture section to drop the discovery/wrapper-function/switcher description and reflect the slimmed plugin scope — verify: re-read the actual plugin file side by side with the updated description and confirm they match
- [x] 4.4 Update `README.md`'s plugin section to mark it optional and scoped to terminal-title only, with a migration note pointing existing `claude-env` users at `ccenv add --discover` — verify: README no longer documents any removed command

## 5. Integration verification

- [x] 5.1 Fresh-shell walkthrough with `ccenv` installed standalone (oh-my-zsh plugin not loaded): exercise all three `add` modes, shell>local>global precedence end to end, `with`, and the after-switch hook — verify: each step's observable output matches its spec scenario
- [x] 5.2 Fresh-shell walkthrough with the slimmed plugin also loaded alongside `ccenv`, then again with `~/.ccenv` temporarily renamed out of the way — verify: the terminal title reflects the profile `ccenv` resolves and exports when both are present; the plugin loads and runs with no errors when `ccenv` is absent entirely
- [x] 5.3 Run `openspec validate redesign-ccenv-cli --strict` — verify: exits 0 with no warnings
