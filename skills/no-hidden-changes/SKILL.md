---
name: no-hidden-changes
description: Use before adopting any change that disables, hides, parks, removes, or relocates something, or uses a custom side-channel (a `_disabled`/`_backup` key or shadow file) instead of a tool's built-in toggle, menu, or setting. Also applies when a change keeps hiding state that has since become valid (stale state lies too), or ships an in-place edit to a versioned/published artifact (plugin, package, shared config) without bumping its version, or installs durable automation (a hook, cron job, launch agent, or background script) without first surveying for an existing mechanism that already does the job or recording what it installed. On first use after install (and once per new project), also reconcile this rule against the user's existing memories / CLAUDE.md / AGENTS.md — and take a one-time inventory of installed automation — surfacing contradictions, duplicates, or undocumented automation before they operate unseen. The test: will a future user opening the tool's own native UI see accurate state, or will it look empty or broken? Prefer the native, visible path; if hidden state is unavoidable, flag it loudly. Don't trigger on benign edits — typos, tests, cosmetic refactors, renames, or honest deletions where nothing is hidden.
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
- Continuing to hide or filter something after the reason for hiding it has expired, so the native view now understates what is actually available.
- Shipping an in-place change to a versioned/published artifact (plugin, package, shared config) without bumping its version.
- Adding a recurring hook, cron job, or launch agent without first checking whether an existing mechanism already does the job — a duplicate hides from every native view.
- Installing durable automation (a hook, cron, agent, watcher, or background script) without recording it anywhere discoverable.

## The one check

> Will a future user or session, opening the tool's OWN native UI, see accurate, non-broken, self-explanatory state?

If the honest answer is "no — it'll look empty, absent, or wrong," the solution is hiding state. Change course or flag it loudly.

## The rule is symmetric: stale state lies too

Hiding is not only an act of *removal* — it is also *failing to restore*. If a change hid or filtered something for a documented reason ("hide the models the gateway can't serve"), and reality later changes so that reason no longer holds, then continuing to hide it makes the native view lie in the other direction: it now understates what is actually available.

Restoring the item **in the spirit of the change's original, documented intent, and telling the user you did it**, is therefore not a hidden change — it is the honest correction. Reflecting real, current state outranks re-asking permission to apply logic the user already approved. Automatic restoration is safe when it is:

- **additive-only and idempotent** — it re-adds, never removes, and does nothing once the item is back;
- **faithful to the documented intent** of the original change; and
- **announced** — the user is told what changed and why.

## Publishing a change: bump the version

Shipping an in-place edit to a versioned or published artifact — a plugin, package, or shared config others install — without bumping its version is itself a hidden change: consumers get different behavior under the same version string, and nothing signals that anything moved. Treat the version number as the discoverable record of the change: bump `plugin.json` (or the equivalent manifest) on every published change, so the swap is visible and attributable rather than silent.

## Survey before you build, and document what you install

Durable automation — a hook, cron job, launch agent, watcher, or background script — is bracketed by two hidden-state traps, one on each side of building it.

**Before building — survey.** Reaching for the most salient tool (a fresh cron, a new script) risks duplicating machinery that already exists. A second mechanism doing a job the first already does is hidden state in the *read* direction: each native surface (the crontab, the launch-agent folder, a hooks config) shows only *itself*, so none of them reveals the duplicate, and a later session meets redundant or conflicting behavior with no single place that explains it. So first scan the surfaces that already hold automation — hooks config, `crontab`, launch agents, `~/.claude/scripts`, scheduled tasks, and your own notes/memory — and extend what's there instead of adding a rival.

**After building — document.** Installing background machinery without recording it anywhere is a hidden change in the *write* direction: the environment now behaves in a way no native UI attributes to anything, so the next session (or user) sees effects with no visible cause and can't tell what installed them, when they fire, or whether they're safe to touch. That's the empty-menu lie, aimed at background behavior instead of a listing. The moment you create durable automation, record it in the most discoverable place available — a memory/index entry, a comment at the install site, a README line — naming the mechanism, the trigger that fires it, and where it lives. Undocumented automation is invisible automation: findable by luck, not by search.

## Prefer native mechanisms

Reach first for what the tool ships with: per-item toggles, documented settings, standard menus, feature flags. These keep the change visible where users expect to find it, and reversible by someone who has never heard of your workaround. A native path that costs a little more is usually worth it.

## When hidden state is truly unavoidable

Sometimes there is no native mechanism. Then treat invisibility as a real cost, not a neutral: surface it loudly, document it in the most discoverable place available, and prefer a form that explains itself in place (a clearly-named marker, an in-UI note) over a silent side-channel. Optimize for the person who will find this later without knowing the trick exists.

## Reconcile with the user's existing guidance

Almost everyone installs this rule *on top of* an existing setup. Old standing
guidance can **contradict**, **duplicate**, or **overlap** it — and letting that
sit unsurfaced is itself a hidden change. So on the first session after install
(a SessionStart banner announces it), once per new project, and reactively when
the rule is about to apply, reconcile it with the user's guidance — **triage
first, and be brief.**

**Triage first — before saying anything.** Silently read the readable guidance
and compare it to the rule:

- **Sources you can read (Claude Code):** global auto-memory (`~/.claude`
  `MEMORY.md` + memory dir) and `CLAUDE.md` / `AGENTS.md`. You **cannot** read
  claude.ai/Desktop custom instructions.
- **Nothing to reconcile** (the common case): write the marker(s) and reply with
  a single line led by 🟢 — *"🟢 Checked your existing setup — zero conflicts,
  nothing to reconcile."* — then go straight to the user's actual request. Do
  **not** explain the feature at length.
- **Something to reconcile:** lead with one 🟡 line — *"🟡 Found N item(s) worth
  reconciling — below."* — then surface it concisely (below). Only in this path,
  add a short note that Desktop custom instructions couldn't be read.

**Surfacing a finding — surface first, change only after an informed, per-item
choice; never silently, never a blind "apply all":**

- **Contradiction** — quote the conflicting instruction **verbatim** and explain
  the clash **neutrally**: both it and the rule as possibly-intentional (no "old
  one is wrong/regretted" framing). Recommend the transparency-improving change,
  but **default to keeping** the existing instruction unless the user actively
  chooses to change it.
- **Duplication** — point out the near-identical rule; propose one canonical
  source. If the near-duplicate is *this plugin's own shipped text* (pasted
  template / reinstall), keep the user's on-disk copy (it survives uninstall).
- **Overlap** — state how you'll reconcile and confirm, per item.

**One informed batch (opt-in):** show **all** proposed before/after diffs
together for a single approval — the user may take the set, a subset, or none.
Review-then-approve, not blind-apply.

**Persisting a resolution:**
- Personal auto-memory / *uncommitted* `CLAUDE.md` → edit in place after
  confirmation; treat the `MEMORY.md` index entry and its linked note as one unit.
- *Committed* `CLAUDE.md`, and **always** `AGENTS.md` (other tools read it) →
  propose a diff to commit; never auto-commit, and flag `AGENTS.md`'s cross-tool reach.
- **Record declines** as durable notes ("kept X over the rule on <date>") and
  respect them — never re-nag a settled decision.

**The once-only marker:** the SessionStart prompt gives you the marker path(s)
and the reconciliation version. Write the version into the marker **only after
the pass completes or the user dismisses it** — never before. An un-acted pass
then simply re-offers next session, so it cannot be lost.

**Automation census (first global pass per machine, or when the installed set
changes).** The same first-run pass also takes a one-time, read-only inventory of
installed automation — Claude Code hooks, `crontab`, launch agents,
`~/.claude/scripts`, and session crons — and cross-checks it against your
discoverable records. Surface it **two-directionally** in the same 🟢/🟡 batch: an
active automation with no record (offer to document it, naming mechanism, trigger,
and location) and a record whose automation no longer exists (offer to correct it),
both DEFAULT-KEEP and per-item, never written silently. Exclude this plugin's own
hook and OS/vendor-managed entries. This clears the *pre-existing* backlog once;
keeping it current afterward is the document-at-install duty above (and the hook's
change-triggered surfaces check) — **not** a recurring scan.

## Canonical anti-pattern

Disabling MCP servers by moving them out of the `mcpServers` config key into a custom `mcpServers_disabled` key. It works — but the native `/mcp` menu then shows up **empty**, which a returning user reads as deceptive or broken. The discoverable alternative: keep the servers registered/visible and use the native per-session disable, accepting the small, honest cost.

## When NOT to apply

This skill is not a tax on ordinary work. Stay quiet for typo fixes, adding tests, cosmetic refactors, renames-for-clarity, and genuine intentional deletions — anything where nothing is being hidden, relocated, or made to fake an empty or broken native view.
