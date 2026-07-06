# Design: first-run self-reconciliation

Date: 2026-07-06 (rev. 2 — incorporates the adversarial multi-agent review)
Status: approved design; ready for implementation plan
Target version: 1.2.0

## Context & motivation

The `no-hidden-changes` plugin ships a standing rule (prefer visible/honest/reversible
changes; don't let a tool's UI misrepresent reality). Almost everyone installs it **on
top of an existing Claude Code history** — accumulated auto-memories, `CLAUDE.md` /
`AGENTS.md`, custom instructions — which can **contradict**, **duplicate**, or **overlap**
the rule. Dropping a new standing rule on top of possibly-conflicting old ones without
surfacing the collision is *itself a hidden change*. So the fix is the plugin **applying
its own principle to its own installation** — not a bolt-on scanner.

## Principle (stays true to a tiny plugin)

The plugin never parses anything; it delegates judgment to Claude via a skill + a
lightweight nudge. This feature does the same: **Claude** reads the guidance and
reconciles. The only machinery is a marker scheme that controls how often the pass runs.

## Lifecycle & activation (verified against Claude Code docs)

- **No install-time hook exists.** `Setup` fires only for `--init-only` / CI runs; hook
  definitions cannot use `once` (skill-frontmatter only). Nothing runs at the instant of
  `/plugin install`.
- **Activation requires a new session.** Newly installed plugin hooks and the skill take
  effect on the **next session start**, not the install session. No live reload.
- **This is well-timed:** rule and reconciliation both come alive at that same next-session
  boundary, and `SessionStart` fires the reconciliation at the very start — before any
  task — so reconciliation precedes the rule's first real application. The only
  unreconciled window is the install session, where the plugin isn't active anyway.
- The README must tell users: **after installing, start a fresh session**; reconciliation
  runs automatically then.

## Trigger — SessionStart, no matcher, marker-written-on-completion

- The `SessionStart` hook runs with **no `matcher`**, so it fires on all session-start
  sources (startup, resume, clear, compact). The **marker — not the matcher — is the
  once-guard**.
- The hook only **detects and offers**: if the relevant marker is absent, it prints (via
  stdout, which SessionStart injects into context) a brief, **non-preemptive** notice +
  offer to reconcile. It does **not** write the marker.
- **Claude writes the marker only after reconciliation completes or is explicitly
  dismissed** (via the skill). Consequences: (a) an un-acted reconciliation **re-offers
  every session until resolved/dismissed** — it can't be silently lost or "burned"; and
  (b) it fixes the "recorded-but-not-performed" bug of writing the marker eagerly in the
  shell.
- **Non-preemptive:** the offer is handled before the user's task unless the user
  redirects; it never blocks the stated task.

### Markers — two scopes, hashed, version-stamped (under `~/.claude/.no-hidden-changes/`)

- **Global** marker: the first-ever reconciliation covers global on-disk guidance + the
  current project; on completion Claude writes both the global marker and this project's
  marker.
- **Per-project** marker: named from a **hash** of the canonical project root —
  `proj_$(printf '%s' "$PWD" | cksum | tr -d ' ')` (`cksum` is POSIX / always present).
  This avoids the collisions and long-filename problems of raw `tr '/ ' '__'` sanitization
  (e.g. `/a/b c` vs `/a/b/c`). Prefer git-toplevel as the project root when available.
- **Version-stamped:** the reconciliation-schema version is written into the marker. A
  future version that ships a broader/better pass compares its version to the stamp and
  runs an incremental pass + re-stamps — so improvements aren't silently skipped on
  already-reconciled installs (which would be the plugin's own anti-pattern).

## Sources reconciled — Claude-Code-reachable only

- **In scope (on disk, readable/editable by Claude Code):** global auto-memory
  (`MEMORY.md` + memory dir) and `CLAUDE.md` / `AGENTS.md`.
- **Out of scope for the Code-side pass:** the user's global **custom instructions** live
  on Anthropic's servers (claude.ai/Desktop) and are invisible to Claude Code. The pass
  must **not** claim to cover them — it tells the user this leg was not reconciled and must
  be reviewed manually in Desktop. (Custom-instruction reconciliation guidance belongs in
  the paste-in template, which is where Desktop users get it.)

## The judgment — neutral surfacing + informed consent

For each relationship, Claude **surfaces first and changes only after an informed,
per-item choice** — never silently, never via a blind "apply all":

- **Contradiction** → name the conflicting instruction, quote its **verbatim** text, and
  explain the clash **neutrally** — present both as possibly-intentional; **no
  "old = regretted" framing**. Recommend the transparency-improving change, but the
  **default on non-response is to keep the existing instruction unchanged**. The user
  actively confirms each change.
- **Duplication** → point out the near-identical rule; propose consolidating to one
  canonical source. If the near-duplicate is the **plugin's own shipped text** (pasted
  template, or a reinstall), bias toward keeping the **user's on-disk copy** (it survives
  uninstall) rather than making the plugin canonical.
- **Overlap / precedence** → state how reconciliation will work and confirm per item.

### Convenient batch (opt-in, still transparent)

Reconciliation is offered with an inviting, low-pressure prompt — e.g. *"Want me to review
your earlier instructions and suggest changes that make your setup more transparent?"* On
yes, Claude presents **all** proposed changes together as a reviewable set of verbatim
before/after diffs. The user may **approve the whole reviewed set** (convenient, but
informed — they saw every diff), approve a subset, or decline. This is the sanctioned form
of "apply all": batch *review-then-approve*, never batch *blind-apply*.

## Persistence

- **Personal auto-memory / uncommitted `CLAUDE.md`** → after confirmation, Claude edits
  directly. For the index+notes memory layout, treat the `MEMORY.md` index entry and its
  linked note as **one unit** — update/remove both, show both in the diff, and register any
  new reconciliation note in the index so it stays authoritative.
- **Shared / committed files (committed `CLAUDE.md`, and always `AGENTS.md`)** → Claude
  proposes the exact **diff** for the user to apply/commit; never auto-commits. For
  `AGENTS.md`, the offer explicitly notes other tools (Cursor, Codex, Aider, …) consume it,
  so the user understands the blast radius before confirming.
- Memory edits are shown as **true line-level diffs** (not paraphrases), so structural
  damage is visible at confirmation time.
- **Declines are recorded** as first-class reconciliation notes ("user chose to keep X over
  the plugin rule on <date>"). Both the proactive and reactive paths check for an existing
  decision before re-surfacing a conflict — a decline is durable, not re-nagged.

## Reactive path (folded in)

The same judgment lives in `SKILL.md`, so beyond the one-time pass, whenever the rule is
about to apply Claude also checks for a conflicting/duplicate user instruction at that
moment, respecting recorded decisions. This is what the copy-paste template relies on
(Desktop/claude.ai have no hook, so they get the reactive form only).

## Non-goals / safety

- **No blind "apply all."** Every change is shown (verbatim before/after) and individually
  consentable; default = keep existing.
- **In-place edits confined to Claude-reachable, non-shared files.** Committed `CLAUDE.md`
  and `AGENTS.md` (cross-tool) are proposed as diffs only.
- **No code-level parsing** of memory formats; Claude does the reading.
- **Never auto-commits** anything.
- Markers live under `~/.claude/`, never in the user's repos.

## Edge cases

- Marker dir unwritable → pass re-offers next session (safe; nothing recorded).
- No existing guidance → Claude reports "nothing to reconcile"; no noise.
- Install session → reconciliation does not run there (hook inactive until next session);
  README documents starting a fresh session.
- Session abandoned mid-reconciliation → marker not written → re-offered next session; no
  loss.
- Hook stays a fast, dependency-light shell check (`cksum` only); no network.

## Components changed

1. `skills/no-hidden-changes/SKILL.md` — reconciliation section (judgment + neutral consent
   + batch offer + persistence + decline records); frontmatter `description` clause.
2. `hooks/hooks.json` — SessionStart, **matcher omitted**, marker-guarded detect+offer
   (Claude writes the version-stamped, `cksum`-hashed markers on completion).
3. `templates/custom-instructions.md` — reactive reconciliation guidance; note the
   Code-only trigger and the custom-instructions / `AGENTS.md` caveats.
4. `README.md` — brief feature mention + "start a fresh session after install" note.
5. `.claude-plugin/plugin.json` — `1.1.0` → `1.2.0`.

## Testing

- Remove markers; simulate SessionStart with a given `$PWD` → the offer is injected and the
  shell writes **no** marker.
- Simulate Claude completing reconciliation → marker written + version-stamped; next
  session prints only the standing nudge.
- Distinct `$PWD`s (including paths with spaces/underscores) → distinct `cksum` markers, no
  collision.
- Decline → decline note recorded; not re-nagged.
- Judgment is model behavior — verified by inspecting the injected instruction and the
  diffs shown, not unit tests.
