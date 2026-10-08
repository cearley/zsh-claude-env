# Design

## Context

The plugin shipped before OpenSpec was adopted in this repo, so no specs existed to describe its behavior. This change has no design decisions to make — it transcribes already-shipped behavior from `zsh-claude-env.plugin.zsh` into spec form.

## Goals / Non-Goals

**Goals:**
- Baseline specs that accurately reflect the plugin's current, shipped behavior.
- A capability boundary per real feature area, so future behavior changes land as focused deltas instead of one monolithic spec.

**Non-Goals:**
- No behavior change of any kind.
- No new config surface, hooks, or capabilities beyond what already exists in code.

## Decisions

### Decision 1: Four capabilities, not one or two

Split along the plugin's existing feature seams — discovery/wrapper generation, session switching, terminal title, and the external extension surface — rather than one catch-all spec. These are the same seams the project's own `CLAUDE.md` already uses to describe the architecture (helpers, title hooks, discovery, wrapper functions, `claude-env`), so the spec boundaries track a division the maintainer already thinks in.

### Decision 2: Source of truth is the code, README is secondary

Every requirement and scenario was checked against `zsh-claude-env.plugin.zsh` directly, not just the README's paraphrase, since the README can drift from the code (e.g. exact validation rules for generated function names, exact hook-invocation timing). Where the two agreed, README prose informed phrasing; where only the code had the detail (e.g. name-character validation, OSC 0 vs OSC 2), the code won.
