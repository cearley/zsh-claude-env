# Spec Delta

## MODIFIED Requirements

### Requirement: After-switch hook point
If a `claude_env_after_switch` function is defined, it SHALL be called with no arguments whenever `ccenv shell` (set or unset) performs an explicit switch. This plugin itself no longer triggers it — the trigger is the standalone `ccenv` CLI (see the `ccenv-resolution` capability). A `cd` that changes the resolved profile with no explicit `ccenv` command run does NOT call it, and neither does `ccenv local`/`ccenv global`; the automatic, directory-triggered side of `ccenv` only keeps `CLAUDE_CONFIG_DIR` correct, it doesn't notify anything. Its presence SHALL be checked at call time, not at plugin-load time, so it is safe to define in a file that sources after this plugin.

#### Scenario: Hook defined after plugin load
- **WHEN** `claude_env_after_switch` is defined later (e.g. in `~/.p10k.zsh`, which sources after this plugin) and the user later runs `ccenv shell <name>`
- **THEN** the hook is called

#### Scenario: ccenv not installed
- **WHEN** `ccenv` is not installed or its shell integration is not active
- **THEN** nothing in this plugin calls `claude_env_after_switch`; `CLAUDE_CONFIG_DIR` simply remains whatever it was last set to, same as before this hook point existed
