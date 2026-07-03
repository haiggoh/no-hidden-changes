---
name: no-hidden-changes
description: Use before adopting any change that disables, hides, parks, removes, or relocates something, or uses a custom side-channel (a `_disabled`/`_backup` key or shadow file) instead of a tool's built-in toggle, menu, or setting. The test: will a future user opening the tool's own native UI see accurate state, or will it look empty or broken? Prefer the native, visible path; if hidden state is unavoidable, flag it loudly. Don't trigger on benign edits — typos, tests, cosmetic refactors, renames, or honest deletions where nothing is hidden.
---

# No Hidden Changes

## The core principle

Prefer solutions that stay **discoverable, honest, and reversible** and that preserve a tool's native, vanilla UX. A clever or cheaper workaround that a future user (or session) can't see is not cheaper — the hidden cost lands later, as confusion or a false impression that something is broken.

## Red-flag signatures

Stop and apply this skill the moment a solution involves any of these:

- Moving, renaming, or commenting-out state/config out of the key, table, file, or directory a tool's own UI, menu, dashboard, or listing reads from.
- A custom side-channel: a `_disabled` / `_backup` / `_old` bucket, a shadow file, or a flag the native UI never reads.
- Suppressing, blanking, or fake-emptying a native view so it shows less than the truth.
- Choosing a bespoke hack over a documented native mechanism (per-item enable/disable, standard settings, a menu, a feature flag).

## The one check

> Will a future user or session, opening the tool's OWN native UI, see accurate, non-broken, self-explanatory state?

If the honest answer is "no — it'll look empty, absent, or wrong," the solution is hiding state. Change course or flag it loudly.

## Prefer native mechanisms

Reach first for what the tool ships with: per-item toggles, documented settings, standard menus, feature flags. These keep the change visible where users expect to find it, and reversible by someone who has never heard of your workaround. A native path that costs a little more is usually worth it.

## When hidden state is truly unavoidable

Sometimes there is no native mechanism. Then treat invisibility as a real cost, not a neutral: surface it loudly, document it in the most discoverable place available, and prefer a form that explains itself in place (a clearly-named marker, an in-UI note) over a silent side-channel. Optimize for the person who will find this later without knowing the trick exists.

## Canonical anti-pattern

Disabling MCP servers by moving them out of the `mcpServers` config key into a custom `mcpServers_disabled` key. It works — but the native `/mcp` menu then shows up **empty**, which a returning user reads as deceptive or broken. The discoverable alternative: keep the servers registered/visible and use the native per-session disable, accepting the small, honest cost.

## When NOT to apply

This skill is not a tax on ordinary work. Stay quiet for typo fixes, adding tests, cosmetic refactors, renames-for-clarity, and genuine intentional deletions — anything where nothing is being hidden, relocated, or made to fake an empty or broken native view.
