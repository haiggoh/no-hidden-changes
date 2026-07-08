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

# Triage epoch — the ONLY thing that gates re-arming the reconciliation.
# Bump this (2, 3, ...) ONLY when the rule text changes in a way that could turn
# a previously-clean triage into a NEW conflict/duplicate finding. Do NOT bump it
# for cosmetic edits, wording tweaks, or ordinary plugin releases — those change
# plugin.json's version, not this. Markers record the epoch they reconciled
# against; an older-or-equal epoch is accepted, a newer epoch re-arms exactly once.
RECON_RULES_VERSION='2'   # 1->2: the first-run pass now ALSO runs a read-only
                          # automation census, so a formerly-clean triage can newly
                          # find undocumented (or stale-documented) automation.
DIR="$HOME/.claude/.no-hidden-changes"
# Global reconciliation is per-HOST. A synced/migrated ~/.claude (dotfiles, Migration
# Assistant, corp-managed home) must NOT carry machine A's "already reconciled" marker
# to machine B — whose crontab and launch agents are its own, unseen automation. Keying
# the global marker by host makes the one-time census run once PER MACHINE, not once ever.
HOST_KEY="$(printf '%s' "$(hostname 2>/dev/null || uname -n)" | cksum | tr -d ' ')"
GLOBAL="$DIR/global-reconciled-${HOST_KEY}"
SURFACES="$DIR/surfaces-${HOST_KEY}"
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

# A marker "counts" (already reconciled — do NOT re-arm) iff its stamped triage
# epoch is >= the current one. Older-or-equal epochs are accepted; re-arming
# happens only when RECON_RULES_VERSION has advanced past what the marker records.
# Legacy markers stamped with a dotted plugin version (e.g. "1.3.0") predate the
# epoch scheme and map to epoch 1. Missing/empty/non-numeric values re-arm (safe:
# the pass simply re-offers next session and cannot be silently lost).
stamped_current() {
  [ -f "$1" ] || return 1
  local v; v="$(cat "$1" 2>/dev/null)"
  case "$v" in *.*) v=1 ;; esac                 # legacy dotted version -> epoch 1
  [ "$v" -ge "$RECON_RULES_VERSION" ] 2>/dev/null
}

# --- automation surfaces fingerprint (cheap change-detector for the census) ---
# Hash the SET of STABLE, user-controllable automation surfaces — NOT their volatile
# runtime state. A change here (a new cron line, launch agent, hook, or script) re-arms
# the one-time census, so automation added AFTER first run — by hand, by another tool,
# or while this plugin was disabled — is still caught. Deliberately EXCLUDES
# `launchctl list` (churns with PIDs/transient jobs -> false re-arms) and system dirs;
# the model's census still reads those live, they just must not drive this check.
surfaces_fingerprint() {
  {
    crontab -l 2>/dev/null
    ls -1 "$HOME/Library/LaunchAgents" 2>/dev/null
    ls -1 "$HOME/.claude/scripts" 2>/dev/null
    grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.claude/settings.json"       2>/dev/null
    grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.claude/settings.local.json" 2>/dev/null
  } 2>/dev/null | cksum | tr -d ' '
}

# Documented test seam: print the fingerprint and exit (used by tests/test_hook.sh).
[ "${NHC_EMIT_SURFACES:-0}" = "1" ] && { surfaces_fingerprint; exit 0; }

# Has the installed-automation set changed since the last census? (Absent baseline
# never re-arms on its own — the first global pass seeds it.)
CUR_SURFACES="$(surfaces_fingerprint)"
surfaces_changed=0
if [ -f "$SURFACES" ]; then
  prev="$(cat "$SURFACES" 2>/dev/null)"
  [ -n "$prev" ] && [ "$prev" != "$CUR_SURFACES" ] && surfaces_changed=1
fi

NUDGE="no-hidden-changes: before any change that disables, hides, parks, removes, or relocates state or config — or reaches for a custom side-channel instead of a native toggle or menu — STOP and consult the no-hidden-changes skill first. Treat a tool no longer showing something in its own UI (or continuing to hide something that has become valid) as a red flag, not a detail."

# Shared triage-first reconciliation instructions (brevity-capped).
COMMON="Follow the skill's \"Reconcile with the user's existing guidance\" section, TRIAGE-FIRST: silently compare the readable guidance (global MEMORY.md + memory dir, CLAUDE.md/AGENTS.md) to the rule BEFORE saying anything. If nothing conflicts or duplicates, write the marker(s) and reply with ONE short line led by 🟢 (e.g. '🟢 Checked your existing setup — zero conflicts, nothing to reconcile.'), then proceed to the user's actual request; do NOT explain the feature at length. If you DO find something, lead with one 🟡 line ('🟡 Found N item(s) worth reconciling — below.'), then surface concisely: quote existing text verbatim, frame NEUTRALLY (both possibly-intentional, no 'old is wrong' framing), DEFAULT TO KEEPING it, make ONE informed batch offer (never blind 'apply all'); only in this path add a short note that claude.ai/Desktop custom instructions could not be read. Persist per the skill: personal auto-memory / uncommitted CLAUDE.md edited in place after confirmation; committed CLAUDE.md and AGENTS.md offered as a diff; record declines as durable notes. Keep total output brief and non-lecturing."

GLOBAL_PROMPT="[no-hidden-changes first-run reconciliation — non-blocking; do it around the user's request, don't derail an urgent task] First session since install on THIS machine (or the set of installed automation changed, or a newer reconciliation version). Do a ONE-TIME triage over the global guidance AND this project. ${COMMON} ALSO run a ONE-TIME, READ-ONLY AUTOMATION CENSUS: enumerate installed automation — Claude Code hooks (~/.claude/settings.json + settings.local.json, and any project .claude/settings.json), the user crontab (crontab -l), launchd agents (~/Library/LaunchAgents + launchctl list), scripts in ~/.claude/scripts, and session crons (CronList) — and cross-check each against your discoverable records (global MEMORY.md + memory dir, CLAUDE.md/AGENTS.md). A finding is EITHER an active automation with NO discoverable record (offer to write a documenting memory/record naming the mechanism, its trigger, and where it lives) OR a record describing automation that no longer exists (offer to correct or remove it). EXCLUDE this plugin's own reconcile-check hook and OS/vendor-managed entries (e.g. Homebrew/Adobe launch agents). Fold census findings into the SAME 🟢/🟡 single batch as the guidance triage — same DEFAULT-KEEP, per-item, confirm-before-writing rules; never write silently. ONLY after the pass completes or the user dismisses it, create dir \"${DIR}\" and write \"${RECON_RULES_VERSION}\" into BOTH \"${GLOBAL}\" and \"${PROJ}\", and write \"${CUR_SURFACES}\" into \"${SURFACES}\". Do not create them beforehand."

PROJ_PROMPT="[no-hidden-changes reconciliation for THIS project — non-blocking] First session for the plugin in this project. Triage this project's CLAUDE.md/AGENTS.md/local guidance against the rule. ${COMMON} ONLY after the pass completes or is dismissed, write \"${RECON_RULES_VERSION}\" into \"${PROJ}\" (create dir \"${DIR}\" first). Do not create it beforehand."

GLOBAL_BANNER="👋 no-hidden-changes active — on your first message I'll do a one-time check of this rule against your existing setup, plus a quick read-only inventory of installed automation (hooks, cron, launch agents, scripts), and flag anything that conflicts or looks undocumented. Nothing changes without your OK."
PROJ_BANNER="👋 no-hidden-changes: new project — on your first message I'll check this rule against this project's guidance. Nothing changes without your OK."

# Decide which (if any) first-run branch applies.
context="$NUDGE"
banner=""
if ! stamped_current "$GLOBAL" || [ "$surfaces_changed" = "1" ]; then
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
