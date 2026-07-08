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

The rule also covers three further cases: **stale state** — continuing to hide
something after it becomes valid is its own hidden change, so restore it (in the
spirit of the original intent) and say so; **version bumps** — shipping an
in-place change to a published/versioned artifact without bumping its version is a
silent swap, so bump `plugin.json` to keep the change visible and attributable; and
**durable automation** — before adding a hook/cron/agent, survey for one that already
does the job (a duplicate hides from every native view), and once you install one,
record it somewhere discoverable (undocumented automation is invisible automation).

**First-run reconciliation (Claude Code):** the first session after you install — once
**per machine** — and once per new project, the plugin does a one-time check of this rule
against your *existing* memories / `CLAUDE.md` / `AGENTS.md`, plus a one-time, read-only
**automation census** of what's already installed (Claude Code hooks, `crontab`, launch
agents, `~/.claude/scripts`, session crons).

What you'll see:
- **At session start**, a short banner — *👋 no-hidden-changes active — on your first message
  I'll check this rule against your existing setup, plus a quick inventory of installed
  automation…* It announces the check; it can't report a result yet (nothing has been read
  at that point).
- **After your first message**, a one-line result: 🟢 *zero conflicts, nothing to reconcile*
  and Claude continues with your request — or 🟡 *found something*, followed by a concise,
  per-item, **verbatim, default-keep** surface and a single informed offer. The census adds
  its findings to the same batch, in both directions: an installed automation with no record
  (offer to document it) and a record whose automation no longer exists (offer to correct it).
  Nothing is rewritten without your confirmation; files other tools read (e.g. `AGENTS.md`)
  are offered as diffs.

Why *per machine*: the reconciliation marker lives in `~/.claude`, which many people sync
across machines — so it's keyed by host, ensuring the census actually runs on each machine
whose crontab/launch agents are its own. After the first pass, the census re-runs only when
the **set of installed automation changes** (a new cron, hook, agent, or script) — it is
change-triggered, not a recurring scan. One honestly-accepted gap: automation hand-installed
outside Claude on a machine you never open a new session on again won't be re-caught; ongoing
coverage is the *document-at-install* habit the rule asks for.

**What it cannot see:** the reconciliation reads your Claude Code memories / `CLAUDE.md` /
`AGENTS.md`, but it **cannot** read your claude.ai / Claude Desktop **Custom Instructions** —
those live server-side, out of a session's reach. If you keep this rule (or one that conflicts
with it) there, review that leg manually in Desktop.

Note that plugin hooks activate on the **next** session, so **start a fresh session after
installing** for the pass to run.

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
