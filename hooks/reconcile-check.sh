#!/usr/bin/env bash
# no-hidden-changes — SessionStart hook.
#
# Emits ONE JSON object on stdout, using the two disjoint hook channels:
#   - hookSpecificOutput.additionalContext : MODEL-only. Always the standing
#     nudge; on a first run it also carries the triage-first reconciliation
#     prompt.
#   - systemMessage (first run only) : USER-visible banner confirming the plugin
#     is active and pre-announcing the one-time reconciliation.
#
# It only DETECTS + OFFERS — it never writes the marker. Claude writes the marker
# (see the skill) only AFTER the pass completes or is dismissed, so an un-acted
# pass simply re-offers next session and cannot be silently lost.
#
# Pure bash (3.2-compatible); no jq/python dependency at runtime.

set -uo pipefail

RECON_VERSION='1.3.0'
DIR="$HOME/.claude/.no-hidden-changes"
GLOBAL="$DIR/global-reconciled"
PROJ_KEY="$(printf '%s' "${PWD:-unknown}" | cksum | tr -d ' ')"
PROJ="$DIR/proj_${PROJ_KEY}"

# --- pure-bash JSON string escaper (bash 3.2 verified) ---
json_escape() {
  local s=$1
  s=${s//\\/\\\\}    # backslash -> \\  (MUST run first)
  s=${s//\"/\\\"}    # "         -> \"
  s=${s//$'\n'/\\n}  # newline   -> \n
  s=${s//$'\t'/\\t}  # tab       -> \t
  s=${s//$'\r'/\\r}  # CR        -> \r
  printf '%s' "$s"
}

# A marker "counts" only if it exists AND its stamp matches the current version.
stamped_current() {
  [ -f "$1" ] || return 1
  [ "$(cat "$1" 2>/dev/null)" = "$RECON_VERSION" ]
}

NUDGE="no-hidden-changes: before any change that disables, hides, parks, removes, or relocates state or config — or reaches for a custom side-channel instead of a native toggle or menu — STOP and consult the no-hidden-changes skill first. Treat a tool no longer showing something in its own UI (or continuing to hide something that has become valid) as a red flag, not a detail."

# Shared triage-first reconciliation instructions (brevity-capped).
COMMON="Follow the skill's \"Reconcile with the user's existing guidance\" section, TRIAGE-FIRST: silently compare the readable guidance (global MEMORY.md + memory dir, CLAUDE.md/AGENTS.md) to the rule BEFORE saying anything. If nothing conflicts or duplicates, write the marker(s) and reply with ONE short line led by 🟢 (e.g. '🟢 Checked your existing setup — zero conflicts, nothing to reconcile.'), then proceed to the user's actual request; do NOT explain the feature at length. If you DO find something, lead with one 🟡 line ('🟡 Found N item(s) worth reconciling — below.'), then surface concisely: quote existing text verbatim, frame NEUTRALLY (both possibly-intentional, no 'old is wrong' framing), DEFAULT TO KEEPING it, make ONE informed batch offer (never blind 'apply all'); only in this path add a short note that claude.ai/Desktop custom instructions could not be read. Persist per the skill: personal auto-memory / uncommitted CLAUDE.md edited in place after confirmation; committed CLAUDE.md and AGENTS.md offered as a diff; record declines as durable notes. Keep total output brief and non-lecturing."

GLOBAL_PROMPT="[no-hidden-changes first-run reconciliation — non-blocking; do it around the user's request, don't derail an urgent task] First session since install (or a newer reconciliation version). Do a ONE-TIME triage over the global guidance AND this project. ${COMMON} ONLY after the pass completes or the user dismisses it, create dir \"${DIR}\" and write \"${RECON_VERSION}\" into BOTH \"${GLOBAL}\" and \"${PROJ}\". Do not create them beforehand."

PROJ_PROMPT="[no-hidden-changes reconciliation for THIS project — non-blocking] First session for the plugin in this project. Triage this project's CLAUDE.md/AGENTS.md/local guidance against the rule. ${COMMON} ONLY after the pass completes or is dismissed, write \"${RECON_VERSION}\" into \"${PROJ}\" (create dir \"${DIR}\" first). Do not create it beforehand."

GLOBAL_BANNER="👋 no-hidden-changes active — on your first message I'll do a one-time check of this rule against your existing setup and flag anything that conflicts. Nothing changes without your OK."
PROJ_BANNER="👋 no-hidden-changes: new project — on your first message I'll check this rule against this project's guidance. Nothing changes without your OK."

# Decide which (if any) first-run branch applies.
context="$NUDGE"
banner=""
if ! stamped_current "$GLOBAL"; then
  context="${NUDGE}"$'\n\n'"${GLOBAL_PROMPT}"
  banner="$GLOBAL_BANNER"
elif ! stamped_current "$PROJ"; then
  context="${NUDGE}"$'\n\n'"${PROJ_PROMPT}"
  banner="$PROJ_BANNER"
fi

# Emit one JSON object. systemMessage only when a banner is set.
if [ -n "$banner" ]; then
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$(json_escape "$banner")" "$(json_escape "$context")"
else
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$(json_escape "$context")"
fi
