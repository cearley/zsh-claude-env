# Design

## Context

See `proposal.md` for motivation, including the empirical test that ruled out shimming the `claude` binary. The relevant constraint it leaves for this document: resolution must work by exporting `CLAUDE_CONFIG_DIR`, computed independently of how any caller (the user's own `claude()` wrapper, `specstory`, `cmux`, or a plain invocation) locates the real binary.

`ccenv` must have zero dependency on `zsh-claude-env.plugin.zsh` or oh-my-zsh; the plugin may depend on `ccenv`, never the reverse. This shapes where the resolution hook lives (see Decisions).

## Goals / Non-Goals

**Goals:**
- `ccenv` works standalone in plain bash/zsh, installed independently of oh-my-zsh.
- Per-directory (`local`), session (`shell`), and machine-wide (`global`) profile resolution, with `shell > local > global` precedence.
- The plugin keeps working with zero `ccenv` installed — it degrades to reading whatever `CLAUDE_CONFIG_DIR` happens to be, same as today.

**Non-Goals:**
- No PATH-based shimming of the `claude` binary (see proposal's empirical finding).
- No bootstrapping of Claude Code itself — `ccenv add <name> --new` creates a directory, not a `.claude.json` (mirrors jenv not installing Java).
- No diagnostic/doctor command in this change (see Open Questions) — not part of the agreed command surface.
- No changes to `specstory`, `cmux`, chezmoi's `claude_default`, or the user's own `claude()` wrapper — flagged as follow-ups in the proposal.

## Decisions

### Keeping CLAUDE_CONFIG_DIR correct mirrors direnv's own hook, not a hand-rolled poll
**Decision**: Only `ccenv shell` (set or `--unset`) touches live, in-session shell state (`CCENV_PROFILE`) that nothing but the calling shell itself can reach, so it alone has an eval target (`sh-shell`) whose output includes the `CLAUDE_CONFIG_DIR` export/unset and the `claude_env_after_switch` call. `ccenv local`/`ccenv global` are both file-only, with no eval-target counterpart (mirroring jenv, which has `jenv-local` but no `jenv-sh-local`) — but the `ccenv()` wrapper calls `_ccenv_hook` directly, as a plain function call, right after either one succeeds, so the live shell still updates within the same command; neither ever fires `claude_env_after_switch`, matching the original plugin's scope (only an explicit `shell`-equivalent switch ever did). Everything else that can change the resolved profile without any `ccenv` command running at all — a new shell starting, or a plain `cd` — is caught by `_ccenv_hook` itself, registered on zsh's `precmd` AND `chpwd` (both — see Alternatives) and bash's `PROMPT_COMMAND` (bash has neither), plus one explicit call right after `ccenv init -` defines it. `_ccenv_hook` is a single line, identical in both shells: `eval "$(command ccenv sh-resolve)"`. Every bit of resolution logic — shell>local>global, computing the real directory, deciding whether it's safe to unset — lives in that one external call (`ccenv sh-resolve`), never duplicated inline; `sh-shell` re-invokes the SAME call rather than keeping its own copy, for the same reason.
**Alternatives considered**: Four earlier iterations, each narrowed by direct inspection of a real reference implementation or a real bug, not by reasoning alone. First: a single `precmd`/`PROMPT_COMMAND` hook re-resolving and re-exporting unconditionally on every prompt, covering every case uniformly (rejected — it conflated "did the directory change" with "did an explicit command run," requiring a last-known-value comparison just to tell those apart, an ownership flag to avoid clobbering an externally-set `CLAUDE_CONFIG_DIR`, and an explicit precmd-ordering fix against the plugin's own title hook). Second: `chpwd` alone for zsh, with the resolution/ownership logic inlined directly in the hook body (rejected after running `direnv hook zsh`/`direnv hook bash` locally — the canonical reference tool registers its hook on **both** `precmd` and `chpwd`, with the *same* trivial one-line body, delegating all logic to one external call rather than inlining it). Third: routing `ccenv local` through its own `sh-local` eval-target too, exactly like `shell` (rejected — jenv has `jenv-local` with NO `jenv-sh-local` counterpart at all; once `_ccenv_hook` fires on every `precmd`, not just `chpwd`, `sh-local`'s synchronous update became redundant with what the very next prompt already does for free). Fourth: after cutting `sh-local`, `sh-shell` kept its OWN copy of the dir-computation/ownership logic rather than reusing `sh-resolve` (rejected on review — the two copies had already drifted: `sh-shell`'s `--unset` path unset `CLAUDE_CONFIG_DIR` unconditionally, with no ownership guard at all, re-clobbering a value ccenv never set; a real, reproduced bug, not a style objection. Collapsing to one writer removed the drift by removing the second copy entirely).
**Consequence**: `_CCENV_LAST_RESOLVED` (profile-name comparison, used only to decide whether to fire a callback automatically) is no longer needed at all, since the automatic path never fires the callback. `_CCENV_DID_EXPORT` (a yes/no ownership flag) becomes `_CCENV_EXPORTED_DIR` (the actual exported value) — the "never touches a value ccenv doesn't own" guarantee applies specifically to the UNSET case (nothing resolves); when something DOES resolve, `ccenv` is authoritative and overwrites unconditionally, including a value the user set by hand after `ccenv` last touched it. The `precmd`-ordering fight with the plugin's title hook disappears: `_ccenv_hook`'s registration (mirroring `direnv hook zsh` exactly) prepends to `precmd_functions`/`chpwd_functions`, and `chpwd` firing synchronously as part of `cd` removes the race entirely. One side effect worth naming: `ccenv global` now affects every shell with integration active — including ones other than the one that ran it — at their next prompt, not only shells started after it runs; this is a genuine behavior change from an earlier draft of this document, judged an improvement (not fought with extra logic to suppress it) once it fell out for free.

### Profiles stored as symlinks, mirroring jenv
**Decision**: `~/.ccenv/profiles/<name>` is a symlink to the real `CLAUDE_CONFIG_DIR` directory, created by `ccenv add`.
**Alternatives considered**: A flat registry file (JSON/TSV mapping name → path) (rejected — needs its own parsing and write-locking code for concurrent shells; a symlink is inspectable with `ls -la`, requires no custom format, and is exactly jenv's own proven approach for `versions/<name>` → JDK home).

### No shims directory
**Decision**: Unlike jenv, `ccenv` installs no `shims/` directory and never intercepts the `claude` binary itself.
**Alternatives considered**: Already covered by the proposal's empirical finding — a shim would be silently bypassed by `specstory`'s own discovery logic, so it would add install-time complexity (another `PATH` entry, a `rehash` step) for zero benefit in the user's actual workflow.

### `ccenv with` replaces generated per-profile functions
**Decision**: One generic `ccenv with <name> <cmd...>` command, implemented as a single script that exports `CLAUDE_CONFIG_DIR` and execs `<cmd>`.
**Alternatives considered**: Keeping the plugin's approach of generating a `claude-<name>` shell function per profile at shell-start (rejected — that machinery exists only to work around not having a generic "run with" primitive; it required templating a function body from a directory name and a character-set validation guard against unsafe names. A single generic command needs no code generation and no such guard, since `<name>` is passed as an ordinary argument, never embedded into generated code).

### Implementation language: POSIX-ish bash/zsh, jenv's `bin`/`libexec` layout
**Decision**: `bin/ccenv` dispatches to `libexec/ccenv-<command>`, one script per subcommand, exactly mirroring jenv's own structure.
**Alternatives considered**: A compiled single-binary implementation (rejected — breaks the `git clone` + zero-build-step install model the user explicitly asked to mirror from jenv; shell is also what the existing plugin and target audience already work in).

### Short aliases (`cenv`, `ccv`) ship alongside the canonical `ccenv` name
**Decision**: Install `bin/cenv` and `bin/ccv` as additional symlinks to the same `libexec/ccenv` dispatcher, so both are full equivalents of `ccenv`, not restricted subsets.
**Alternatives considered**: Shipping only `ccenv` (rejected — the user wants a short day-to-day name, the same pattern CLI tools distributed via package managers like `uv tool install` often follow by registering multiple entry points for one underlying tool). Using `cenv` as the *primary* name (already rejected earlier in this change for colliding with existing conda and Node.js tools of the same name — see `proposal.md`'s naming history). As a secondary, opt-in alias the risk is different: it only matters if the user's own `PATH` also contains one of those other `cenv` tools, in which case ordinary `PATH`-order shadowing decides which wins — the same risk any shell alias carries, not something unique to this choice.

## Risks / Trade-offs

- [Risk] If the user's machine also has conda's `cenv-tool` or the Node.js `cenv` CLI on `PATH`, the `cenv` alias will collide with one of them depending on `PATH` order. → *Mitigation*: none built in; document it in the README's naming note, and rely on `~/.ccenv/bin` being early in `PATH` (as the install instructions already have the user do) if they want this alias to resolve to `ccenv`.

- [Risk] A user installs `ccenv` but never adds `eval "$(ccenv init -)"` to their shell startup, so `shell`/`local`/`global` state changes silently do nothing. → *Mitigation*: `ccenv init -` sets a marker (e.g. `CCENV_LOADED=1`), and state-mutating subcommands (`shell`, `local`, `global`) check for it, printing a warning to stderr when it's absent instead of silently appearing to succeed.
- [Risk] The real directory behind a registered profile is deleted or moved after `ccenv add`, leaving a dangling symlink. → *Mitigation*: `ccenv list` and resolution both detect a dangling symlink and report it rather than silently exporting a path to nothing.
- [Risk] Removing the plugin's discovery/switcher functions is a breaking change for the user's own existing muscle memory and chezmoi config (`claude_default`). → *Mitigation*: README migration section pointing at `ccenv add --discover`; the chezmoi-side swap to `ccenv global` is an explicit, separate follow-up already called out in the proposal as out of scope here.
- [Risk] `_ccenv_hook` forks a subprocess (`ccenv sh-resolve`) on every `precmd` AND `chpwd` fire, not just on an actual change — measured at ~37ms per fork, so ~74ms added to every `cd` (both hooks fire) and ~37ms to every other prompt. This contradicts an earlier version of this document, which claimed "no subprocess forks" on the (now-superseded) assumption that resolution would only run on `chpwd` and be inlined rather than delegated to a forked call. → *Mitigation*: accepted, not engineered around — direnv itself, the reference implementation this mirrors, forks on every `precmd` and `chpwd` fire too (confirmed: `direnv export <shell>` is a full subprocess call, same as `ccenv sh-resolve`), and is used interactively by a large population without this being a reported problem in practice. If this ever needs to be cut, the first lever is reducing registration to `chpwd`-only again (dropping `precmd`), accepting slightly staler correctness (by the next prompt, not synchronously on `cd`) in exchange for roughly half the fork frequency — not something this change does by default, since direnv's own choice to accept the cost on both is evidence it's the right default.
- [Risk] One repo with two independent install paths could confuse a reader about what's required vs. optional. → *Mitigation*: README leads with the standalone `ccenv` install as primary; the oh-my-zsh plugin section is clearly marked optional and scoped to "terminal-title only."

## Migration Plan

1. Build `ccenv` as a purely additive change first (new `bin/`, `libexec/` files; the existing plugin is untouched and still fully functional) so the new CLI can be exercised and verified standalone before anything is removed.
2. Once `ccenv` is verified working (profiles resolve correctly, `with` runs commands correctly, shell integration survives a new shell session), slim the plugin in a second pass: remove discovery, generated functions, and `claude-env`; modify the after-switch hook requirement; keep terminal-title and the other hooks untouched.
3. Update `README.md` with both install paths and a short migration note (`ccenv add --discover` to bulk-import existing `~/.claude-*` directories) and `CLAUDE.md` to reflect the new architecture.
4. Tag a new version once both passes land, consistent with this project's existing manual-tagging practice (`v0.1.0`, `v0.2.0`, `v0.2.1`) — this change warrants a major-looking bump given the explicit breaking removal, though exact scheme is left to the user at tag time.

Rollback is a plain `git revert`; no persistent state beyond symlinks and a couple of small config files is created, and none of it is destructive to the user's actual Claude Code data (profiles only ever point at existing directories, never move or copy them).

## Open Questions

- Exact wording of the `ccenv add <name> --new` next-step hint (whether it prints the suggested `ccenv with <name> claude` bootstrap command, or leaves that entirely to the README) — a copy detail, doesn't change the requirement or its scenarios.
- Whether a `ccenv doctor` diagnostic command (jenv parity) is worth adding in a later change — intentionally not part of this change's command surface; raised here only so it isn't forgotten.
