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
for the three relationships to this rule. In **every** case Claude *surfaces the conflict
in-session first, and changes things only after the user chooses* — never silently:

- **Contradiction** → name the conflicting instruction and explain the clash.
  **Precedence: installing this plugin is treated as opting into its paradigm, so the
  paradigm takes precedence over _older_ instructions that contradict it** — those may be
  an approach the user now regrets. Claude therefore *nudges the user to accept a
  transparent, automatic overhaul* of the conflicting instruction so it matches the new
  paradigm. This is a recommendation resolved in-session, not a silent override: Claude
  shows the exact change and the user actively confirms (and may decline / keep the old
  instruction).
- **Duplication** → point out the near-identical existing rule; propose consolidating to
  one canonical source so they don't diverge. User picks which is authoritative.
- **Overlap / precedence** → state how reconciliation will work and confirm.

### Persistence & transparent overhaul

Reconciliation is resolved interactively in-session (so the user can choose when their
preference isn't obvious up front), and the chosen resolution is then **persisted** so the
same conflict doesn't resurface:

- **Personal auto-memory / custom instructions** → after the user confirms, Claude edits
  the note directly: update or remove the contradicting instruction, or consolidate
  duplicates into one canonical source.
- **Shared / committed files** (a project `CLAUDE.md`/`AGENTS.md` under git) → Claude
  proposes the exact diff and lets the user apply/commit it themselves. It never
  auto-commits team-shared config.
- Every change is **shown before it is applied and recorded** (a brief reconciliation note
  in memory), so the overhaul is discoverable later — an overhaul in the open, not a silent
  rewrite. Same reasoning as the v1.1.0 corollary: a change made in the spirit of a
  paradigm the user opted into, confirmed and announced, is not a hidden change.

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

- **Edits only after in-session confirmation, always transparently.** Claude shows the
  exact before/after and records the change; it never silently rewrites anything. A
  confirmed, shown, recorded overhaul is not a hidden change — it is the paradigm the user
  opted into, applied in the open.
- **Shared/committed files are proposed, never auto-committed.** For a project `CLAUDE.md`
  under git, Claude offers the diff; the user applies and commits it.
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
