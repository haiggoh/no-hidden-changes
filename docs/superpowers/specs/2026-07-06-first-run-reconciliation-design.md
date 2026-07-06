# Design: first-run self-reconciliation

Date: 2026-07-06
Status: approved (brainstorming) — pending implementation plan
Target version: 1.2.0

## Context & motivation

The `no-hidden-changes` plugin ships a standing rule (prefer visible/honest/reversible
changes; don't let a tool's UI misrepresent reality). Almost everyone installs it **on
top of an existing Claude Code history** — accumulated auto-memories, `CLAUDE.md` /
`AGENTS.md` files, and custom instructions. That pre-existing standing guidance can:

1. **Contradict** the rule — e.g. an old note "park unused MCP servers in a
   `mcpServers_disabled` key to save cost" is exactly this plugin's canonical
   anti-pattern. Two live rules pull opposite ways, and the older one may win silently.
2. **Duplicate** it — a user's own "prefer visible changes" note now coexists with the
   plugin's; the two word-drift over time and neither is clearly canonical.
3. **Overlap / need precedence** — related-but-not-identical guidance with no stated
   rule for which wins.

Dropping a new standing rule on top of possibly-conflicting old ones, without surfacing
the collision, is **itself a hidden change**. So the fix is not a bolt-on scanner — it
is the plugin **applying its own principle to its own installation**.

## Principle (why this stays true to a tiny plugin)

The plugin never parses anything; it delegates judgment to Claude via a skill + a
lightweight nudge. This feature does the same: **Claude** reads the existing guidance
and reconciles. No memory-parser in code. The only machinery is a marker that makes the
proactive pass fire the right number of times.

## Behavior

### The judgment (shared by proactive + reactive paths)

When reconciling, Claude reviews the user's standing guidance — global auto-memory
(`MEMORY.md` + memory dir), `CLAUDE.md` / `AGENTS.md`, and custom instructions in scope —
for the three relationships to this rule, and in **every** case *surfaces and proposes*,
never silently changes anything:

- **Contradiction** → name the conflicting instruction and explain the clash. Precedence:
  an explicit user instruction still wins (user instructions override skills), BUT the
  conflict must be surfaced, never silently resolved. If the old note is an anti-pattern
  the user now wants to drop, offer to update it (only with the user's say-so).
- **Duplication** → point out the near-identical existing rule; propose consolidating to
  one canonical source so they don't diverge. User picks which is authoritative.
- **Overlap / precedence** → state how reconciliation will work and confirm.

### When the proactive pass fires (two markers, both under `~/.claude/`)

- **Global-first:** on the first-ever session after install (global marker absent), run a
  FULL pass — global guidance + the current project's `CLAUDE.md`/local guidance — then
  create BOTH the global marker and this project's marker (this project is now covered).
- **Project-first:** in a project whose marker is absent (but global marker present), run
  a PROJECT pass over that project's `CLAUDE.md`/local guidance; create the project marker.
- **Otherwise:** only the normal standing nudge prints.

This yields exactly one reconciliation globally, plus one per distinct project — never
repeating.

### Reactive path (folded-in B)

The same judgment lives in `SKILL.md`, so even outside the one-time pass, whenever the
rule is about to apply Claude also checks for a conflicting/duplicate user instruction at
that moment and surfaces it. This is what the copy-paste template relies on (see below).

## Components changed

1. **`skills/no-hidden-changes/SKILL.md`** — add a section, e.g. "Reconcile with the
   user's existing guidance," carrying the judgment above (proactive-on-first-encounter +
   reactive-when-applying). Add a one-line note to the frontmatter `description` so the
   skill triggers when reconciliation is warranted.

2. **`hooks/hooks.json`** — the `SessionStart` command gains a marker-guarded branch.
   Dependency-free shell (no new script, no network):
   - Global marker: `~/.claude/.no-hidden-changes/global-reconciled`
   - Project marker: `~/.claude/.no-hidden-changes/proj_<sanitized $PWD>` (sanitize by
     `tr '/ ' '__'` — avoids depending on a hashing binary and never writes inside the repo)
   - Always `printf` the standing nudge; prepend/append the appropriate reconciliation
     instruction on global-first or project-first; `mkdir -p` the dir and create markers.

3. **`templates/custom-instructions.md`** — add the reconciliation guidance (reactive
   form). Explicitly note the *one-time proactive trigger is Claude-Code-only*, because
   Desktop/claude.ai have no hook system.

4. **`README.md`** — brief mention of first-run reconciliation.

5. **`.claude-plugin/plugin.json`** — bump `1.1.0` → `1.2.0` (new feature).

## Non-goals / safety

- **Never auto-edits** the user's memories, `CLAUDE.md`, or custom instructions — only
  surfaces and proposes. Auto-editing their notes would itself be a hidden change.
- **No code-level parsing** of memory formats; Claude does the reading.
- Markers live under `~/.claude/`, never in the user's repos.

## Edge cases

- **Marker dir unwritable** → pass may re-fire; harmless (the instruction is safe to
  repeat, and finds nothing new to surface).
- **No existing guidance** → Claude reports "nothing to reconcile"; no noise.
- **Hook must never break/delay startup** → pure `test`/`printf`/`: >`; no network.

## Testing

- Remove markers, run the hook command with a fake `$PWD` → confirm it emits the
  reconciliation instruction and creates the correct marker(s).
- Run again (markers present) → confirm only the standing nudge prints.
- Confirm a fresh project dir (new `$PWD`) triggers the project pass once.
- The judgment itself is model behavior — verified by inspecting the injected instruction,
  not unit tests.
