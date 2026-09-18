#!/usr/bin/env bash
# Framework-free tests for reconcile-check.sh. Requires bash + jq (test-only).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/reconcile-check.sh"
# Read the triage epoch the hook currently gates on, so the test tracks it.
RECON_RULES_VERSION="$(sed -nE "s/^RECON_RULES_VERSION='([^']*)'.*/\1/p" "$HOOK" | head -1)"
# Global + surfaces markers are keyed by host (mirrors the hook). Derive the same key.
HOST_KEY="$(printf '%s' "$(hostname 2>/dev/null || uname -n)" | cksum | tr -d ' ')"
GMARK="global-reconciled-${HOST_KEY}"
SMARK="surfaces-${HOST_KEY}"

pass=0; fail=0
check() { if [ "$1" -eq 0 ]; then echo "  PASS: $2"; pass=$((pass+1)); else echo "  FAIL: $2"; fail=$((fail+1)); fi; }
sysmsg() { jq -r '.systemMessage // ""' "$1"; }
ctx()    { jq -r '.hookSpecificOutput.additionalContext' "$1"; }
# </dev/null on both: these cases exercise the hook's reconcile LOGIC, not its stdin
# handling, so they must not inherit the caller's fd0. Two reasons. The hook reads stdin
# when fd0 is not a terminal, so inheriting it (a) makes every case pay the read's
# timeout when the caller holds stdin open, and (b) lets the hook CONSUME the caller's
# own input — if the caller is a shell reading its script from stdin, that swallows the
# rest of the script. Case I is the one place stdin shape is deliberately the subject.
run()    { ( cd "$2" && HOME="$1" bash "$HOOK" </dev/null ); }   # run <home> <cwd>
fp()     { NHC_EMIT_SURFACES=1 HOME="$1" bash "$HOOK" </dev/null; }  # surfaces fingerprint for a HOME

command -v jq >/dev/null 2>&1 || { echo "jq required for tests"; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CWD="$TMP/proj"; mkdir -p "$CWD"

echo "== Case A: no markers (global first-run) =="
HA="$TMP/home_a"; mkdir -p "$HA"
OUT="$TMP/a.json"; run "$HA" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON"
[ -n "$(sysmsg "$OUT")" ]; check $? "systemMessage present"
case "$(sysmsg "$OUT")" in *"active"*) r=0;; *) r=1;; esac; check $r "global banner wording"
case "$(sysmsg "$OUT")" in *"inventory of installed automation"*) r=0;; *) r=1;; esac; check $r "banner mentions automation inventory"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "reconciliation prompt present"
case "$(ctx "$OUT")" in *"TRIAGE-FIRST"*) r=0;; *) r=1;; esac; check $r "triage-first instruction present"
case "$(ctx "$OUT")" in *"AUTOMATION CENSUS"*) r=0;; *) r=1;; esac; check $r "census present in global prompt"

echo "== Case B: global done, project not (per-project first-run) =="
HB="$TMP/home_b"; mkdir -p "$HB/.claude/.no-hidden-changes"
printf '%s' "$RECON_RULES_VERSION" > "$HB/.claude/.no-hidden-changes/$GMARK"
OUT="$TMP/b.json"; run "$HB" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON"
case "$(sysmsg "$OUT")" in *"new project"*) r=0;; *) r=1;; esac; check $r "project banner wording"
case "$(ctx "$OUT")" in *"AUTOMATION CENSUS"*) r=1;; *) r=0;; esac; check $r "census ABSENT in per-project prompt (global-only)"

echo "== Case C: both markers present (steady state) =="
HC="$TMP/home_c"; DC="$HC/.claude/.no-hidden-changes"; mkdir -p "$DC"
printf '%s' "$RECON_RULES_VERSION" > "$DC/$GMARK"
# Derive the key exactly as the hook does, from the same cwd (avoids symlink drift).
KEY="$(cd "$CWD" && printf '%s' "$PWD" | cksum | tr -d ' ')"
printf '%s' "$RECON_RULES_VERSION" > "$DC/proj_${KEY}"
OUT="$TMP/c.json"; run "$HC" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON"
[ -z "$(sysmsg "$OUT")" ]; check $? "no systemMessage in steady state"
case "$(ctx "$OUT")" in *"before any change that disables"*) r=0;; *) r=1;; esac; check $r "nudge present"
case "$(ctx "$OUT")" in *reconciliation*) r=1;; *) r=0;; esac; check $r "no reconciliation prompt in steady state"

echo "== Case D: legacy dotted markers (pre-epoch) now RE-ARM (epoch advanced 1->$RECON_RULES_VERSION) =="
HD="$TMP/home_d"; DD="$HD/.claude/.no-hidden-changes"; mkdir -p "$DD"
KEY="$(cd "$CWD" && printf '%s' "$PWD" | cksum | tr -d ' ')"
printf '%s' "1.3.0" > "$DD/$GMARK"     # old semver stamp -> epoch 1, now < current
printf '%s' "1.3.0" > "$DD/proj_${KEY}"
OUT="$TMP/d.json"; run "$HD" "$CWD" > "$OUT"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "legacy dotted marker re-arms (epoch advanced)"
case "$(ctx "$OUT")" in *"AUTOMATION CENSUS"*) r=0;; *) r=1;; esac; check $r "re-armed pass carries the census"

echo "== Case E: stale epoch (below current) re-arms =="
HE="$TMP/home_e"; DE="$HE/.claude/.no-hidden-changes"; mkdir -p "$DE"
printf '%s' "0" > "$DE/$GMARK"          # epoch 0 < current -> re-arm
OUT="$TMP/e.json"; run "$HE" "$CWD" > "$OUT"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "stale epoch re-arms reconciliation"

echo "== Case F: non-numeric / garbage marker re-arms (fails safe) =="
HF="$TMP/home_f"; DF="$HF/.claude/.no-hidden-changes"; mkdir -p "$DF"
printf '%s' "notanumber" > "$DF/$GMARK"
OUT="$TMP/f.json"; run "$HF" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON despite garbage marker"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "garbage marker re-arms (fails safe)"

echo "== Case G: per-host — a synced marker for a DIFFERENT host does not count =="
HG="$TMP/home_g"; DG="$HG/.claude/.no-hidden-changes"; mkdir -p "$DG"
printf '%s' "$RECON_RULES_VERSION" > "$DG/global-reconciled-99999999"   # another machine's marker
# current host's marker is absent -> must re-arm (census must run on THIS machine)
OUT="$TMP/g.json"; run "$HG" "$CWD" > "$OUT"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "foreign-host marker ignored, census re-arms on this host"

echo "== Case H: surfaces-hash backstop (change-triggered re-arm) =="
HH="$TMP/home_h"; DH="$HH/.claude/.no-hidden-changes"; mkdir -p "$DH"
KEY="$(cd "$CWD" && printf '%s' "$PWD" | cksum | tr -d ' ')"
printf '%s' "$RECON_RULES_VERSION" > "$DH/$GMARK"
printf '%s' "$RECON_RULES_VERSION" > "$DH/proj_${KEY}"
# H1: surfaces baseline matches current fingerprint -> no re-arm
printf '%s' "$(fp "$HH")" > "$DH/$SMARK"
OUT="$TMP/h1.json"; run "$HH" "$CWD" > "$OUT"
case "$(ctx "$OUT")" in *reconciliation*) r=1;; *) r=0;; esac; check $r "unchanged surfaces -> no re-arm"
# H2: surfaces baseline differs -> re-arm with census
printf '%s' "0" > "$DH/$SMARK"
OUT="$TMP/h2.json"; run "$HH" "$CWD" > "$OUT"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "changed surfaces re-arm reconciliation"
case "$(ctx "$OUT")" in *"AUTOMATION CENSUS"*) r=0;; *) r=1;; esac; check $r "surface-change pass carries the census"

echo "== Case I: stdin that never reaches EOF must not hang the hook =="
# A SessionStart hook runs before the session is usable, so an unbounded read is not a
# slow test — it is a stalled startup. `[ ! -t 0 ]` does NOT distinguish "a pipe that
# will reach EOF" from "a pipe/socket the caller holds open", so this case supplies the
# second kind: a FIFO whose write end this shell keeps open, meaning EOF never arrives.
HI="$TMP/home_i"; mkdir -p "$HI"
FIFO="$TMP/never-eof"; mkfifo "$FIFO"
exec 3<>"$FIFO"                     # read-write: a writer always exists, so no EOF, ever
OUT="$TMP/i.json"
( cd "$CWD" && HOME="$HI" bash "$HOOK" <&3 ) > "$OUT" 2>/dev/null &
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

echo; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
