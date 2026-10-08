# terminal-title Specification

## Purpose
Keeps the terminal/tab title in sync with the active Claude environment, repo, branch, and running job, without conflicting with a terminal that already manages its own titles.

## Requirements

### Requirement: Title content and format
On each prompt render and before each command, the plugin SHALL set the terminal title via an OSC 0 escape sequence to `✳ <env> · <repo> · <branch> · <job>`, in that general-to-specific order, omitting any segment that is unavailable (no active environment, not in a git repo, no branch, no job) without leaving a stray or doubled `·` separator.

#### Scenario: All segments available
- **WHEN** an environment is active, the shell is in a git repo on a branch, and a command is about to run
- **THEN** the title is set to `✳ <env> · <repo> · <branch> · <job>`

#### Scenario: No active environment
- **WHEN** no Claude environment is active but the shell is in a git repo
- **THEN** the title omits the `✳ <env>` segment and begins directly with `<repo>`

#### Scenario: Not in a git repository
- **WHEN** an environment is active but the current directory is not inside a git work tree
- **THEN** the title omits the repo/branch segment entirely, with no stray separator

### Requirement: Job segment reflects prompt vs. command
At the prompt (precmd), the job segment SHALL be the literal value `zsh`. Immediately before a command executes (preexec), the job segment SHALL be the first whitespace-delimited word of that command.

#### Scenario: Idle prompt
- **WHEN** the shell is sitting at an idle prompt
- **THEN** the title's job segment is `zsh`

#### Scenario: Command about to run
- **WHEN** the user runs `npm run build --watch`
- **THEN** the title's job segment becomes `npm` just before execution

### Requirement: Title hooks can be disabled
Setting `CLAUDE_ENV_TITLE_HOOKS=false` SHALL suppress all title updates from this plugin. The value SHALL be read at each hook invocation (not only at plugin load), so it can be set after the plugin has already loaded (e.g. in `~/.p10k.zsh`, which sources afterward) and still take effect.

#### Scenario: Disabled before plugin loads
- **WHEN** `CLAUDE_ENV_TITLE_HOOKS=false` is set before the plugin sources
- **THEN** no title updates occur

#### Scenario: Disabled after plugin loads
- **WHEN** the plugin has already loaded with hooks active, and `CLAUDE_ENV_TITLE_HOOKS=false` is then set (e.g. from `~/.p10k.zsh`)
- **THEN** subsequent prompts and commands stop updating the title

### Requirement: Defer to a terminal's own title management
If the environment variable `GHOSTTY_SHELL_FEATURES` contains `title`, indicating the terminal already writes its own title every prompt, the plugin's title hooks SHALL no-op entirely rather than also writing a title.

#### Scenario: Terminal manages titles
- **WHEN** `GHOSTTY_SHELL_FEATURES` contains `title`
- **THEN** precmd and preexec produce no title output from this plugin

#### Scenario: Terminal does not manage titles
- **WHEN** `GHOSTTY_SHELL_FEATURES` is unset or does not contain `title`
- **THEN** the plugin's title hooks run normally (subject to `CLAUDE_ENV_TITLE_HOOKS`)
