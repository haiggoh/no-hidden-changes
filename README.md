# no-hidden-changes

A tiny Claude behavior rule: **prefer visible, honest, reversible changes over
hidden-state workarounds.** When a fix would move or hide state where a tool's own
UI can't show it — leaving a native menu empty or a dashboard lying — this steers
Claude to the discoverable, native path instead, or to flag the trade-off out loud.

It ships two ways: a one-click **Claude Code plugin** (a skill + a one-line
session nudge), and a copy-paste **Custom Instructions** block for Claude Desktop
and claude.ai (which have no plugin system).

## Why

The rule came from a real moment. To cut token cost, some MCP servers were
"parked" by moving them out of the `mcpServers` config key into a custom
`mcpServers_disabled` key. It worked — but the native `/mcp` menu then showed up
**empty**, which reads as deceptive or broken to anyone coming back later. The
honest alternative (keep them registered/visible, use the native per-session
disable) preserved the vanilla UX. Generalized, that lesson is this project:
don't make a tool's own UI lie about its state.

## Install — Claude Code (one-click)

```
/plugin marketplace add haiggoh/no-hidden-changes
/plugin install no-hidden-changes@haiggoh
```

You get:
- a `no-hidden-changes` **skill** (visible in `/skills`, zero token cost until
  invoked) carrying the full guidance, and
- a one-line **SessionStart hook** that reminds Claude the skill exists so it
  fires at the right moment.

The rule also covers two symmetric cases: **stale state** — continuing to hide
something after it becomes valid is its own hidden change, so restore it (in the
spirit of the original intent) and say so — and **version bumps** — shipping an
in-place change to a published/versioned artifact without bumping its version is a
silent swap, so bump `plugin.json` to keep the change visible and attributable.

## Install — Claude Desktop / claude.ai (copy-paste)

These apps have no plugin marketplace. Open
[`templates/custom-instructions.md`](templates/custom-instructions.md) and paste
the rule block into **Settings → Custom Instructions** (or a Project's
instructions).

## How it works

Skills are model-invoked: Claude consults one when the task matches its
description. The description here is tuned to fire the moment a change would hide
state, and to stay quiet on benign edits (typos, tests, renames, honest
deletions). The session nudge is a lightweight pointer that raises the odds the
skill fires when it matters — the same pattern the Superpowers framework uses.

It is **guidance, not a hard gate**: it prompts Claude to prefer the visible path
or flag the trade-off, not to block anything.

## License

MIT © Heiko Brantsch
