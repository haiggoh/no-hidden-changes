#!/usr/bin/env bash
# Framework-free tests for reconcile-check.sh. Requires bash + jq (test-only).
#
# v2.0.0 contract: the reconciliation re-arms ONLY on a triage-epoch advance (or a
# missing / garbage / foreign-host marker). Specifically:
#   - NO per-project trigger: a stamped global marker is steady state in EVERY cwd.
#   - NO installed-automation surfaces fingerprint: churn in ~/.claude/scripts,
#     settings files, crontab or LaunchAgents never re-arms anything (v1.x hashed
#     ~/.claude/scripts — a workspace sessions write into near-daily — and re-armed
#     the banner almost every day).
#   - The global marker is keyed by a STABLE machine identity (IOPlatformUUID), not
#     by hostname (which flaps with the network — measured: two host-key generations
#     born 3 hours apart). The pre-2.0 hostname-keyed marker is still ACCEPTED, so
#     upgrading does not re-arm existing installs.
#   - The snooze is global-only and its validity is epoch-only.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/reconcile-check.sh"
# Read the triage epoch the hook currently gates on, so the test tracks it.
RECON_RULES_VERSION="$(sed -nE "s/^RECON_RULES_VERSION='([^']*)'.*/\1/p" "$HOOK" | head -1)"

pass=0; fail=0
check() { if [ "$1" -eq 0 ]; then echo "  PASS: $2"; pass=$((pass+1)); else echo "  FAIL: $2"; fail=$((fail+1)); fi; }
sysmsg() { jq -r '.systemMessage // ""' "$1"; }
ctx()    { jq -r '.hookSpecificOutput.additionalContext' "$1"; }
# </dev/null on both: these cases exercise the hook's reconcile LOGIC, not its stdin
# handling, so they must not inherit the caller's fd0 (see Case Z for the one case
# where stdin shape IS the subject).
run()    { ( cd "$2" && HOME="$1" bash "$HOOK" </dev/null ); }   # run <home> <cwd>

# Marker keys come from the hook's own documented seam, never re-derived here.
# Re-deriving the machine identity in the test is exactly the hostname/UUID drift
# the seam exists to kill.
hostkeys() { NHC_EMIT_HOST_KEY=1 HOME="$1" bash "$HOOK" </dev/null; }
mkey() { hostkeys "$1" | sed -n 's/^machine //p'; }
lkey() { hostkeys "$1" | sed -n 's/^legacy //p'; }
gmark() { printf 'global-reconciled-%s' "$(mkey "$1")"; }
lmark() { printf 'global-reconciled-%s' "$(lkey "$1")"; }

# A populated scripts workspace. Sessions drop helper scripts here CONSTANTLY
# (measured: six files changed in one day on the author's machine), which is what
# made the v1.x fingerprint re-arm the banner near-daily. Every steady-state case
# below runs WITH this dir present, so the suite catches any reintroduction of a
# scripts-sensitive check — not just an exact replay of the old fingerprint.
seed_scripts_workspace() {
  mkdir -p "$1/.claude/scripts"
  printf '#!/bin/sh\n' > "$1/.claude/scripts/helper-one.sh"
}
# Add churn AFTER a baseline was stamped — the realistic re-arm shape.
churn_scripts_workspace() {
  printf '#!/bin/sh\n' > "$1/.claude/scripts/helper-two.sh"
}

command -v jq >/dev/null 2>&1 || { echo "jq required for tests"; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CWD="$TMP/proj"; mkdir -p "$CWD"

echo "== Case A: no markers (global first-run) =="
HA="$TMP/home_a"; mkdir -p "$HA"
seed_scripts_workspace "$HA"
OUT="$TMP/a.json"; run "$HA" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON"
[ -n "$(sysmsg "$OUT")" ]; r=$?; check $r "systemMessage present"
case "$(sysmsg "$OUT")" in *"active"*) r=0;; *) r=1;; esac; check $r "global banner wording"
case "$(sysmsg "$OUT")" in *"inventory of installed automation"*) r=0;; *) r=1;; esac; check $r "banner mentions automation inventory"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "reconciliation prompt present"
case "$(ctx "$OUT")" in *"TRIAGE-FIRST"*) r=0;; *) r=1;; esac; check $r "triage-first instruction present"
case "$(ctx "$OUT")" in *"AUTOMATION CENSUS"*) r=0;; *) r=1;; esac; check $r "census present in global prompt"

echo "== Case B: global stamped, scripts dir populated, ANY cwd -> steady state (no per-project trigger) =="
HB="$TMP/home_b"; DB="$HB/.claude/.no-hidden-changes"; mkdir -p "$DB"
seed_scripts_workspace "$HB"
printf '%s' "$RECON_RULES_VERSION" > "$DB/$(gmark "$HB")"
OUT="$TMP/b.json"; run "$HB" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON"
[ -z "$(sysmsg "$OUT")" ]; r=$?; check $r "no systemMessage: a stamped global marker is steady state in every project"
case "$(ctx "$OUT")" in *"before any change that disables"*) r=0;; *) r=1;; esac; check $r "nudge present"
case "$(ctx "$OUT")" in *reconciliation*) r=1;; *) r=0;; esac; check $r "no reconciliation prompt in steady state"
case "$(ctx "$OUT")" in *"AUTOMATION CENSUS"*) r=1;; *) r=0;; esac; check $r "census absent in steady state"

echo "== Case C: surfaces baseline present + scripts churned -> STILL steady state =="
# The exact v1.x state that re-armed the banner near-daily: a stored surfaces
# baseline that no longer matches the live scripts dir. v2 must ignore the file.
HC="$TMP/home_c"; DC="$HC/.claude/.no-hidden-changes"; mkdir -p "$DC"
seed_scripts_workspace "$HC"
printf '%s' "$RECON_RULES_VERSION" > "$DC/$(gmark "$HC")"
printf '%s' "$RECON_RULES_VERSION" > "$DC/$(lmark "$HC")"   # stamped under both key schemes
printf '%s' "0" > "$DC/surfaces-$(lkey "$HC")"              # stale baseline under the legacy key name
printf '%s' "0" > "$DC/surfaces-$(mkey "$HC")"              # ...and under the machine key name
churn_scripts_workspace "$HC"
OUT="$TMP/c.json"; run "$HC" "$CWD" > "$OUT"
[ -z "$(sysmsg "$OUT")" ]; r=$?; check $r "stale surfaces baseline + churn does not re-arm"
case "$(ctx "$OUT")" in *reconciliation*) r=1;; *) r=0;; esac; check $r "no reconciliation prompt despite surfaces churn"

echo "== Case D: legacy dotted markers (pre-epoch) re-arm (epoch advanced) =="
HD="$TMP/home_d"; DD="$HD/.claude/.no-hidden-changes"; mkdir -p "$DD"
printf '%s' "1.3.0" > "$DD/$(gmark "$HD")"     # old semver stamp -> epoch 1, now < current
OUT="$TMP/d.json"; run "$HD" "$CWD" > "$OUT"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "legacy dotted marker re-arms (epoch advanced)"
case "$(ctx "$OUT")" in *"AUTOMATION CENSUS"*) r=0;; *) r=1;; esac; check $r "re-armed pass carries the census"

echo "== Case E: stale epoch (below current) re-arms =="
HE="$TMP/home_e"; DE="$HE/.claude/.no-hidden-changes"; mkdir -p "$DE"
printf '%s' "0" > "$DE/$(gmark "$HE")"          # epoch 0 < current -> re-arm
OUT="$TMP/e.json"; run "$HE" "$CWD" > "$OUT"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "stale epoch re-arms reconciliation"

echo "== Case F: non-numeric / garbage marker re-arms (fails safe) =="
HF="$TMP/home_f"; DF="$HF/.claude/.no-hidden-changes"; mkdir -p "$DF"
printf '%s' "notanumber" > "$DF/$(gmark "$HF")"
OUT="$TMP/f.json"; run "$HF" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON despite garbage marker"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "garbage marker re-arms (fails safe)"

echo "== Case G: per-host — a synced marker for a DIFFERENT host does not count =="
HG="$TMP/home_g"; DG="$HG/.claude/.no-hidden-changes"; mkdir -p "$DG"
printf '%s' "$RECON_RULES_VERSION" > "$DG/global-reconciled-99999999"   # another machine's marker
# current machine's marker is absent -> must re-arm (census must run on THIS machine)
OUT="$TMP/g.json"; run "$HG" "$CWD" > "$OUT"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "foreign-host marker ignored, census re-arms on this host"

echo "== Case H: pre-2.0 hostname-keyed marker is ACCEPTED (upgrade must not re-arm) =="
HH="$TMP/home_h"; DH="$HH/.claude/.no-hidden-changes"; mkdir -p "$DH"
seed_scripts_workspace "$HH"
printf '%s' "$RECON_RULES_VERSION" > "$DH/$(lmark "$HH")"   # ONLY the legacy key
OUT="$TMP/h.json"; run "$HH" "$CWD" > "$OUT"
[ -z "$(sysmsg "$OUT")" ]; r=$?; check $r "legacy hostname-keyed marker accepted, no banner"
case "$(ctx "$OUT")" in *reconciliation*) r=1;; *) r=0;; esac; check $r "no reconciliation prompt with legacy marker only"

echo "== Case I: marker keys are stable and distinct =="
HI="$TMP/home_i"; mkdir -p "$HI"
K1="$(mkey "$HI")"; K2="$(mkey "$HI")"; L1="$(lkey "$HI")"
[ -n "$K1" ]; r=$?; check $r "machine key non-empty"
[ "$K1" = "$K2" ]; r=$?; check $r "machine key stable across runs"
[ -n "$L1" ]; r=$?; check $r "legacy key non-empty"

echo "== Case J: snoozed global, epoch matches (new epoch|date format) -> deferred =="
HJ="$TMP/home_j"; DJ="$HJ/.claude/.no-hidden-changes"; mkdir -p "$DJ"
seed_scripts_workspace "$HJ"
printf '%s|%s' "$RECON_RULES_VERSION" "$(date +%Y-%m-%d)" > "$DJ/global-snoozed-$(mkey "$HJ")"
OUT="$TMP/j.json"; run "$HJ" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON"
case "$(sysmsg "$OUT")" in *"deferred"*) r=0;; *) r=1;; esac; check $r "snoozed banner says deferred"
case "$(sysmsg "$OUT")" in *"available on request"*) r=0;; *) r=1;; esac; check $r "snoozed banner offers on request"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=1;; *) r=0;; esac; check $r "NO reconciliation prompt when snoozed"

echo "== Case K: snoozed global SURVIVES scripts churn (epoch-only validity) =="
HK="$TMP/home_k"; DK="$HK/.claude/.no-hidden-changes"; mkdir -p "$DK"
seed_scripts_workspace "$HK"
printf '%s|%s' "$RECON_RULES_VERSION" "$(date +%Y-%m-%d)" > "$DK/global-snoozed-$(mkey "$HK")"
churn_scripts_workspace "$HK"
OUT="$TMP/k.json"; run "$HK" "$CWD" > "$OUT"
case "$(sysmsg "$OUT")" in *"deferred"*) r=0;; *) r=1;; esac; check $r "snooze survives automation churn (epoch-only)"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=1;; *) r=0;; esac; check $r "NO reconciliation prompt after churn while snoozed"

echo "== Case L: legacy 3-field snooze format (epoch|surfaces|date) still parses =="
HL="$TMP/home_l"; DL="$HL/.claude/.no-hidden-changes"; mkdir -p "$DL"
printf '%s|%s|2026-01-01' "$RECON_RULES_VERSION" "35951711312281" > "$DL/global-snoozed-$(mkey "$HL")"
OUT="$TMP/l.json"; run "$HL" "$CWD" > "$OUT"
case "$(sysmsg "$OUT")" in *"deferred"*) r=0;; *) r=1;; esac; check $r "legacy snooze format still valid (epoch field honoured)"

echo "== Case M: snoozed global with stale epoch re-arms =="
HM="$TMP/home_m"; DM="$HM/.claude/.no-hidden-changes"; mkdir -p "$DM"
printf '%s|%s' "1" "$(date +%Y-%m-%d)" > "$DM/global-snoozed-$(mkey "$HM")"
OUT="$TMP/m.json"; run "$HM" "$CWD" > "$OUT"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "snooze with stale epoch re-arms"

echo "== Case N: prompt text contract — no per-project / surfaces marker writes, no automation-change trigger =="
HN="$TMP/home_n"; mkdir -p "$HN"
OUT="$TMP/n.json"; run "$HN" "$CWD" > "$OUT"
PROMPT="$(ctx "$OUT")"
case "$PROMPT" in *"proj_"*) r=1;; *) r=0;; esac; check $r "prompt never instructs writing a proj_ marker"
case "$PROMPT" in *"surfaces-"*) r=1;; *) r=0;; esac; check $r "prompt never instructs writing a surfaces marker"
case "$PROMPT" in *"installed automation changed"*) r=1;; *) r=0;; esac; check $r "prompt no longer claims re-arm on automation change"
case "$PROMPT" in *"First session since install on THIS machine, or a newer reconciliation version"*) r=0;; *) r=1;; esac; check $r "trigger text names machine + epoch only"

echo "== Case Z: stdin that never reaches EOF must not hang the hook =="
# A SessionStart hook runs before the session is usable, so an unbounded read is not a
# slow test — it is a stalled startup. `[ ! -t 0 ]` does NOT distinguish "a pipe that
# will reach EOF" from "a pipe/socket the caller holds open", so this case supplies the
# second kind: a FIFO whose write end this shell keeps open, meaning EOF never arrives.
HZ="$TMP/home_z"; mkdir -p "$HZ"
FIFO="$TMP/never-eof"; mkfifo "$FIFO"
exec 3<>"$FIFO"                     # read-write: a writer always exists, so no EOF, ever
OUT="$TMP/z.json"
( cd "$CWD" && HOME="$HZ" bash "$HOOK" <&3 ) > "$OUT" 2>/dev/null &
HOOKPID=$!
i=0
while kill -0 "$HOOKPID" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i+1)); done
if kill -0 "$HOOKPID" 2>/dev/null; then
  # Reap the blocked reader too, or a regression leaves a stuck process behind. Direct
  # children only: without setsid there is no private process group to signal here.
  pkill -P "$HOOKPID" 2>/dev/null || true
  kill "$HOOKPID" 2>/dev/null; wait "$HOOKPID" 2>/dev/null
  check 1 "hook returns within 3s when stdin never reaches EOF (it blocked)"
  check 1 "hook still emits valid JSON on a never-EOF stdin (never returned)"
else
  wait "$HOOKPID" 2>/dev/null
  check 0 "hook returns within 3s when stdin never reaches EOF"
  jq . "$OUT" >/dev/null 2>&1; check $? "hook still emits valid JSON on a never-EOF stdin"
fi
exec 3>&-

# --- the NUDGE must carry the reflex-commit shapes -------------------------------------
# The nudge is the only surface that reaches EVERY session regardless of model, so it is where
# the always-on rules have to live. These were added after a GATEWAY session committed straight
# to main on four repos in one sitting while the rule existed only in memory and in the free-lane
# system prompt — proof that a rule not on this surface gets missed.
NH="$TMP/home_nudge"; mkdir -p "$NH"
NOUT="$TMP/nudge.json"
( HOME="$NH" bash "$HOOK" </dev/null ) > "$NOUT" 2>/dev/null
NUDGE="$(ctx "$NOUT")"

for probe in \
  "EDIT THE SOURCE, NOT A DERIVED COPY" \
  "plugins/cache" \
  "BRANCH, and stage BY PATH" \
  "git add -A" \
  "worktree" \
  "NEVER force-push" \
  "fix forward" \
  "EXACT NAME" \
  "check-ignore" \
  "no output is the warning"
do
  case "$NUDGE" in
    *"$probe"*) check 0 "the nudge carries: $probe" ;;
    *) check 1 "the nudge carries: $probe" ;;
  esac
done

# Credit-moment mark (plan 2026-10-28, W3 Task 9, amended by the user 2026-10-31): the nudge and
# the SNOOZED status banner carry the About-emoji 👁️; the FIRST-RUN banner keeps 👋 — it is a
# greeting ("hi, this plugin is here and would like a quick check"), not a violation mark.
case "$NUDGE" in
  "👁️ no-hidden-changes: before any change that disables"*) check 0 "the nudge leads with '👁️ no-hidden-changes:'" ;;
  *) check 1 "the nudge leads with '👁️ no-hidden-changes:'" ;;
esac
for frag in 'GLOBAL_BANNER="👋 no-hidden-changes active' 'GLOBAL_BANNER_SNOOZED="👁️ no-hidden-changes: reconciliation deferred'; do
  case "$(cat "$HERE/../hooks/reconcile-check.sh")" in
    *"$frag"*) check 0 "banner pinned: ${frag%% no*}" ;;
    *) check 1 "banner pinned: $frag" ;;
  esac
done

# A code span must survive as a LITERAL backtick. Passing prose through a double-quoted shell
# string command-substitutes a span and silently deletes it while the command still exits 0,
# so this asserts the stored text rather than trusting the writer.
case "$NUDGE" in
  *'`git add -A`'*) check 0 "a code span in the nudge keeps its literal backticks" ;;
  *) check 1 "a code span in the nudge keeps its literal backticks" ;;
esac
case "$NUDGE" in
  *'`git check-ignore -v <path>`'*) check 0 "the check-ignore span keeps its literal backticks" ;;
  *) check 1 "the check-ignore span keeps its literal backticks" ;;
esac
# …and the apostrophe in "the user's unsaved work" survived the same quoting.
case "$NUDGE" in
  *"user's unsaved work"*) check 0 "an apostrophe in the nudge survives shell quoting" ;;
  *) check 1 "an apostrophe in the nudge survives shell quoting" ;;
esac

# The skill's own frontmatter must be parseable YAML. A description containing a colon-space
# must be QUOTED or a strict parser rejects the whole file and the skill never loads.
python3 - "$HERE/../skills/no-hidden-changes/SKILL.md" <<'PYCHK'
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
fm = open(sys.argv[1]).read().split("---\n")[1]
d = yaml.safe_load(fm)
assert isinstance(d, dict) and "description" in d, "frontmatter must define a description"
PYCHK
check $? "the skill's frontmatter is valid YAML (a colon-space description must be quoted)"

echo; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
