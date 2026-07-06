#!/usr/bin/env bash
# no-hidden-changes — SessionStart hook.
#
# Always prints the standing nudge. Additionally, once globally and once per
# project, it OFFERS a reconciliation of the plugin's rule with the user's
# pre-existing on-disk guidance. It only DETECTS + OFFERS — it never writes the
# marker itself. Claude writes the marker (see the skill) only AFTER the pass is
# completed or dismissed, so an un-acted pass simply re-offers next session and
# cannot be silently "burned" or lost.
#
# stdout from a SessionStart hook is injected into Claude's context.

set -uo pipefail

RECON_VERSION='1.2.0'
DIR="$HOME/.claude/.no-hidden-changes"
GLOBAL="$DIR/global-reconciled"
# Per-project marker keyed by a collision-resistant hash of $PWD (cksum is POSIX,
# always present) — avoids the path collisions of naive character substitution.
PROJ_KEY="$(printf '%s' "${PWD:-unknown}" | cksum | tr -d ' ')"
PROJ="$DIR/proj_${PROJ_KEY}"

NUDGE="no-hidden-changes: before any change that disables, hides, parks, removes, or relocates state or config — or reaches for a custom side-channel instead of a native toggle or menu — STOP and consult the no-hidden-changes skill first. Treat a tool no longer showing something in its own UI (or continuing to hide something that has become valid) as a red flag, not a detail."

# A marker "counts" only if it exists AND its stamp matches the current version,
# so a future reconciliation version re-runs instead of being silently skipped.
stamped_current() {
  [ -f "$1" ] || return 1
  [ "$(cat "$1" 2>/dev/null)" = "$RECON_VERSION" ]
}

COMMON="Follow the skill's \"Reconcile with the user's existing guidance\" section. Sources you CAN read here: global auto-memory (~/.claude MEMORY.md + memory dir) and CLAUDE.md/AGENTS.md. You CANNOT read the user's claude.ai/Desktop custom instructions — say so plainly, do not claim to have covered them. Surface conflicts NEUTRALLY (present the existing instruction and the plugin rule as both possibly-intentional; no 'old is wrong/regretted' framing), quote existing text verbatim, and DEFAULT TO KEEPING it unless the user actively chooses to change it — never a blind 'apply all'. You may open with an inviting offer like: 'Want me to review your earlier instructions and suggest changes that make your setup more transparent?' and, on yes, show ALL proposed before/after diffs together for one informed approval. Edit personal auto-memory / uncommitted CLAUDE.md in place after confirmation (treat the MEMORY.md index entry and its linked note as one unit); for committed CLAUDE.md and for AGENTS.md (other tools read it) propose a diff to commit rather than editing in place. Record declines as durable notes and respect them."

# Always emit the standing nudge.
printf '%s' "$NUDGE"

if ! stamped_current "$GLOBAL"; then
  printf '\n\n[no-hidden-changes FIRST-RUN reconciliation — non-blocking; do it before or around the user request, do not derail an urgent task] First session since the plugin was installed (or a newer reconciliation version shipped). Run a ONE-TIME pass over the global standing guidance AND this project. %s ONLY after the pass is completed or the user dismisses it, persist it so it does not repeat: create the dir "%s" and write "%s" into BOTH "%s" and "%s". Do not create them beforehand.' "$COMMON" "$DIR" "$RECON_VERSION" "$GLOBAL" "$PROJ"
elif ! stamped_current "$PROJ"; then
  printf '\n\n[no-hidden-changes reconciliation for THIS project — non-blocking] First session for the plugin in this project. Reconcile this project'\''s CLAUDE.md/AGENTS.md/local guidance with the rule. %s ONLY after the pass is completed or dismissed, write "%s" into "%s" (create dir "%s" first). Do not create it beforehand.' "$COMMON" "$RECON_VERSION" "$PROJ" "$DIR"
fi
