#!/usr/bin/env bash
# Framework-free tests for reconcile-check.sh. Requires bash + jq (test-only).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/reconcile-check.sh"
# Read the version the hook currently stamps, so the test is version-agnostic.
RECON_VERSION="$(sed -nE "s/^RECON_VERSION='([^']*)'.*/\1/p" "$HOOK" | head -1)"

pass=0; fail=0
check() { if [ "$1" -eq 0 ]; then echo "  PASS: $2"; pass=$((pass+1)); else echo "  FAIL: $2"; fail=$((fail+1)); fi; }
sysmsg() { jq -r '.systemMessage // ""' "$1"; }
ctx()    { jq -r '.hookSpecificOutput.additionalContext' "$1"; }
run()    { ( cd "$2" && HOME="$1" bash "$HOOK" ); }   # run <home> <cwd>

command -v jq >/dev/null 2>&1 || { echo "jq required for tests"; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CWD="$TMP/proj"; mkdir -p "$CWD"

echo "== Case A: no markers (global first-run) =="
HA="$TMP/home_a"; mkdir -p "$HA"
OUT="$TMP/a.json"; run "$HA" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON"
[ -n "$(sysmsg "$OUT")" ]; check $? "systemMessage present"
case "$(sysmsg "$OUT")" in *"active"*) r=0;; *) r=1;; esac; check $r "global banner wording"
case "$(ctx "$OUT")" in *"first-run reconciliation"*) r=0;; *) r=1;; esac; check $r "reconciliation prompt present"
case "$(ctx "$OUT")" in *"TRIAGE-FIRST"*) r=0;; *) r=1;; esac; check $r "triage-first instruction present"

echo "== Case B: global done, project not (per-project first-run) =="
HB="$TMP/home_b"; mkdir -p "$HB/.claude/.no-hidden-changes"
printf '%s' "$RECON_VERSION" > "$HB/.claude/.no-hidden-changes/global-reconciled"
OUT="$TMP/b.json"; run "$HB" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON"
case "$(sysmsg "$OUT")" in *"new project"*) r=0;; *) r=1;; esac; check $r "project banner wording"

echo "== Case C: both markers present (steady state) =="
HC="$TMP/home_c"; DC="$HC/.claude/.no-hidden-changes"; mkdir -p "$DC"
printf '%s' "$RECON_VERSION" > "$DC/global-reconciled"
# Derive the key exactly as the hook does, from the same cwd (avoids symlink drift).
KEY="$(cd "$CWD" && printf '%s' "$PWD" | cksum | tr -d ' ')"
printf '%s' "$RECON_VERSION" > "$DC/proj_${KEY}"
OUT="$TMP/c.json"; run "$HC" "$CWD" > "$OUT"
jq . "$OUT" >/dev/null 2>&1; check $? "valid JSON"
[ -z "$(sysmsg "$OUT")" ]; check $? "no systemMessage in steady state"
case "$(ctx "$OUT")" in *"before any change that disables"*) r=0;; *) r=1;; esac; check $r "nudge present"
case "$(ctx "$OUT")" in *reconciliation*) r=1;; *) r=0;; esac; check $r "no reconciliation prompt in steady state"

echo; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
