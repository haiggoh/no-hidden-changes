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
# v2.0.0 re-arm contract — the reconciliation is GLOBAL and epoch-gated. It
# re-arms ONLY when the triage epoch advances (a semantic change to the rule),
# when no valid marker exists (first run per machine, corruption), or on a
# different machine. It deliberately does NOT re-arm on: a new project (no
# per-project pass exists), new scripts/automation (the v1.x surfaces
# fingerprint hashed ~/.claude/scripts — a workspace sessions write into
# near-daily — and re-armed the banner almost every day), or a hostname change
# (the marker key no longer derives from the network-dependent hostname).
# Ongoing automation coverage is the document-at-install duty in the skill, not
# a hook-side change detector.
#
# Pure bash (3.2-compatible); no jq/python dependency at runtime.
#
# Cross-plugin ordering: this hook is meant to be the FIRST SessionStart banner to
# land (resume-interrupted and waypoints sequence themselves after it — see their own
# hooks). It never waits on anything itself; it just signals "done deciding" as soon as
# it has emitted its output, via a session-scoped flag any other plugin's hook may poll:
# `$TMPDIR-or-/tmp/claude-sessionstart-banners/<session_id>.no-hidden-changes.done`. This
# is one-way and best-effort — a missing/unparseable session_id just means no flag is
# written, which never blocks this hook's own output.

set -uo pipefail

# This is a SessionStart hook: the harness invokes it with a JSON payload on stdin
# and no arguments. --help is still supported so a human probing it gets a usage
# line instead of JSON spew — and never an unintended run (parsing happens before
# any work, per the repo's scripts-support-help rule).
usage() {
  cat <<'USAGE'
no-hidden-changes reconcile-check — SessionStart hook.

Runs at session start; decides whether the one-time reconciliation (rule triage +
read-only automation census) should be offered, and emits ONE JSON object on stdout
for the harness. It never writes any marker itself — the model writes markers only
after the pass completes (see skills/no-hidden-changes/SKILL.md).

Usage: reconcile-check.sh [--help]

Arguments:
  --help, -h   Show this help and exit.

Environment variables:
  NHC_EMIT_HOST_KEY=1   Print the machine + legacy marker keys and exit (test seam).

Input: one JSON object on stdin (the harness's SessionStart payload); a missing or
never-EOF payload degrades gracefully.
USAGE
}
case "${1-}" in
  -h|--help) usage; exit 0 ;;
  "") : ;;
  *) printf 'reconcile-check.sh: unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
esac

# Read the hook's stdin JSON once, defensively, and with a BOUND.
#
# `-t 0` alone is not enough. It distinguishes a terminal from "not a terminal", but the
# non-terminal case has two shapes: a pipe that will reach EOF (the real SessionStart
# invocation) and a pipe or socket the CALLER HOLDS OPEN and never closes (an agent's
# shell tool, a CI runner, a test harness). An unbounded `cat` returns for the first and
# blocks forever on the second — and because this is a SessionStart hook, blocking here
# does not merely slow something down, it stalls the start of the session.
#
# `read -t 1 -d ''` covers both: EOF ends the read immediately, so a real piped payload
# costs nothing, while a never-closing caller costs at most one second. It returns
# non-zero on timeout but still populates the variable with whatever arrived, which is
# why the `|| true` is load-bearing rather than decorative. Integer timeout only: bash
# 3.2 predates fractional `-t`.
STDIN_JSON=""
if [ ! -t 0 ]; then
  IFS= read -r -t 1 -d '' STDIN_JSON 2>/dev/null || true
fi
SESSION_ID="$(printf '%s' "$STDIN_JSON" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

_banner_flag_dir() {
  printf '%s' "${TMPDIR:-${XDG_RUNTIME_DIR:-/tmp}}/claude-sessionstart-banners"
}

# Best-effort, session-scoped "I'm done deciding" flag for any OTHER plugin's
# SessionStart hook to optionally poll on. Never blocks; sid-less sessions get no flag
# since nothing could key on them anyway. Always called via `trap ... EXIT` below so it
# fires on every exit path, not just the success path.
_signal_done() {
  [ -n "$SESSION_ID" ] || return 0
  local dir; dir="$(_banner_flag_dir)"
  mkdir -p "$dir" 2>/dev/null && chmod 700 "$dir" 2>/dev/null || return 0
  local path="$dir/${SESSION_ID}.no-hidden-changes.done"
  local tmp="${path}.tmp.$$"
  printf 'producer=no-hidden-changes\n' > "$tmp" 2>/dev/null && mv -f "$tmp" "$path" 2>/dev/null
}
trap _signal_done EXIT

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

# Machine identity for the global marker. v1.x keyed this on $(hostname), which on
# macOS is network-dependent — a DHCP search domain attaches and detaches as the
# machine moves between networks — so every hostname flap re-armed the banner as a
# "first session on this machine" (measured: two host-key generations born three
# hours apart). IOPlatformUUID is stable across networks, reboots and OS updates.
# hostname remains only as (a) the fallback where ioreg is unavailable (non-macOS)
# and (b) the LEGACY marker key still accepted when the machine-keyed marker is
# absent, so a 1.x install that already reconciled does not re-arm on upgrade.
_machine_uuid() {
  ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null \
    | sed -n 's/.*"IOPlatformUUID"[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1 || true
}
MACHINE_ID="$(_machine_uuid)"
[ -n "$MACHINE_ID" ] || MACHINE_ID="$(hostname 2>/dev/null || uname -n)"
HOST_KEY="$(printf '%s' "$MACHINE_ID" | cksum | tr -d ' ')"
LEGACY_HOST_KEY="$(printf '%s' "$(hostname 2>/dev/null || uname -n)" | cksum | tr -d ' ')"
GLOBAL="$DIR/global-reconciled-${HOST_KEY}"
GLOBAL_LEGACY="$DIR/global-reconciled-${LEGACY_HOST_KEY}"
GLOBAL_SNOOZE="$DIR/global-snoozed-${HOST_KEY}"

# Documented test seam: print the machine + legacy marker keys and exit
# (used by tests/test_hook.sh — deriving the keys anywhere else is the drift
# this seam exists to kill).
[ "${NHC_EMIT_HOST_KEY:-0}" = "1" ] && { printf 'machine %s\nlegacy %s\n' "$HOST_KEY" "$LEGACY_HOST_KEY"; exit 0; }

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

# A snooze is valid while its stamped epoch equals the current one. (The pre-2.0
# three-field format epoch|surfaces|date still parses: the surfaces field is
# simply ignored — v2 removed the automation-set change detector, so nothing may
# expire a snooze except the epoch.) It is only consulted when no reconciled
# marker qualifies: a completed pass outranks a deferred one.
snoozed_valid() {
  local snooze_file="$1"
  [ -f "$snooze_file" ] || return 1
  local content; content="$(cat "$snooze_file" 2>/dev/null)"
  [ -n "$content" ] || return 1
  local snooze_epoch; snooze_epoch="$(printf '%s' "$content" | cut -d'|' -f1)"
  [ "$snooze_epoch" = "$RECON_RULES_VERSION" ]
}

NUDGE="no-hidden-changes: before any change that disables, hides, parks, removes, or relocates state or config — or reaches for a custom side-channel instead of a native toggle or menu — STOP and consult the no-hidden-changes skill first. Treat a tool no longer showing something in its own UI (or continuing to hide something that has become valid) as a red flag, not a detail. Three shapes of this are easy to commit by reflex, so check them BEFORE you start editing rather than at commit time: (1) EDIT THE SOURCE, NOT A DERIVED COPY — an installed plugin cache (~/.claude/plugins/cache/...), a symlinked live file, or a generated config is overwritten by the next update with no error and no version change, so the fix silently reverts and cannot ship; find the source repo and change that. Note the installed copy may also be OLDER than the repo, so confirm which one your change must reach. (2) BRANCH, and stage BY PATH — do not accumulate unrelated edits and land them on the default branch as one lump, and never \`git add -A\`, which stages the user's unsaved work too; and an ignore rule by EXACT NAME protects only the file it names, so run \`git check-ignore -v <path>\` before the FIRST commit of any new private file (no output is the warning), and widen the pattern rather than adding names one at a time; if a checkout is reached through symlinks or a launcher, its branch is global state, so use a worktree instead of switching it. (3) NEVER force-push or move a published tag unasked — fix forward as the next version; a rewrite does not even remove a leaked secret."

# Shared triage-first reconciliation instructions (brevity-capped).
COMMON="Follow the skill's \"Reconcile with the user's existing guidance\" section, TRIAGE-FIRST: silently compare the readable guidance (global MEMORY.md + memory dir, CLAUDE.md/AGENTS.md) to the rule BEFORE saying anything. If nothing conflicts or duplicates, write the marker(s) and reply with ONE short line led by 🟢 (e.g. '🟢 Checked your existing setup — zero conflicts, nothing to reconcile.'), then proceed to the user's actual request; do NOT explain the feature at length. If you DO find something, lead with one 🟡 line ('🟡 Found N item(s) worth reconciling — below.'), then surface concisely: quote existing text verbatim, frame NEUTRALLY (both possibly-intentional, no 'old is wrong' framing), DEFAULT TO KEEPING it, make ONE informed batch offer (never blind 'apply all'); only in this path add a short note that claude.ai/Desktop custom instructions could not be read. Persist per the skill: personal auto-memory / uncommitted CLAUDE.md edited in place after confirmation; committed CLAUDE.md and AGENTS.md offered as a diff; record declines as durable notes. Keep total output brief and non-lecturing."

GLOBAL_PROMPT="[no-hidden-changes first-run reconciliation — non-blocking; do it around the user's request, don't derail an urgent task] First session since install on THIS machine, or a newer reconciliation version. Do a ONE-TIME triage over the global guidance AND this project. ${COMMON} ALSO run a ONE-TIME, READ-ONLY AUTOMATION CENSUS: enumerate installed automation — Claude Code hooks (~/.claude/settings.json + settings.local.json, and any project .claude/settings.json), the user crontab (crontab -l), launchd agents (~/Library/LaunchAgents + launchctl list), scripts in ~/.claude/scripts, and session crons (CronList) — and cross-check each against your discoverable records (global MEMORY.md + memory dir, CLAUDE.md/AGENTS.md). A finding is EITHER an active automation with NO discoverable record (offer to write a documenting memory/record naming the mechanism, its trigger, and where it lives) OR a record describing automation that no longer exists (offer to correct or remove it). EXCLUDE this plugin's own reconcile-check hook and OS/vendor-managed entries (e.g. Homebrew/Adobe launch agents). Fold census findings into the SAME 🟢/🟡 single batch as the guidance triage — same DEFAULT-KEEP, per-item, confirm-before-writing rules; never write silently. ONLY after the pass completes or the user dismisses it, create dir \"${DIR}\" and write \"${RECON_RULES_VERSION}\" into \"${GLOBAL}\". Do not create it beforehand."

GLOBAL_BANNER="👋 no-hidden-changes active — on your first message I'll do a one-time check of this rule against your existing setup, plus a quick read-only inventory of installed automation (hooks, cron, launch agents, scripts), and flag anything that conflicts or looks undocumented. Nothing changes without your OK."
GLOBAL_BANNER_SNOOZED="👋 no-hidden-changes: reconciliation deferred since $(date '+%Y-%m-%d') — available on request."

# Decide whether the first-run branch applies. The ONLY re-arm triggers are:
#   - no valid marker (first run per machine, corruption, garbage)
#   - an advanced triage epoch (a semantic change to the rule)
#   - a different machine (foreign-host markers never count)
# Nothing else re-arms: not a new project, not new scripts, not a hostname change.
context="$NUDGE"
banner=""
if ! stamped_current "$GLOBAL" && ! stamped_current "$GLOBAL_LEGACY"; then
  if snoozed_valid "$GLOBAL_SNOOZE"; then
    banner="$GLOBAL_BANNER_SNOOZED"
  else
    context="${NUDGE}"$'\n\n'"${GLOBAL_PROMPT}"
    banner="$GLOBAL_BANNER"
  fi
fi

# Emit one JSON object. systemMessage only when a banner is set.
if [ -n "$banner" ]; then
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$(json_escape "$banner")" "$(json_escape "$context")"
else
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$(json_escape "$context")"
fi
