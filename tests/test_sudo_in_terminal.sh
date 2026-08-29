#!/usr/bin/env bash
# Framework-free test for scripts/sudo-in-terminal.sh.
#
# The password path cannot be tested unattended, and that is fine: the three
# behaviours worth guarding are all reachable without one. The important one is
# ALREADY_SATISFIED — the script must NOT open a window when the desired state
# already holds, or the visible path degrades into a nag.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/sudo-in-terminal.sh"
fail=0
check() { if [ "$1" = 0 ]; then echo "  ok: $2"; else echo "  FAIL: $2"; fail=1; fi; }

[ -x "$SCRIPT" ]; check $? "script is present and executable"

# 1) --command is required
OUT="$(bash "$SCRIPT" 2>&1)"; rc=$?
[ "$rc" = 2 ]; check $? "missing --command exits 2"
case "$OUT" in *"--command is required"*) check 0 "and says why";; *) check 1 "and says why ($OUT)";; esac

# 2) an unknown argument is refused rather than ignored
OUT="$(bash "$SCRIPT" --nonsense x 2>&1)"; rc=$?
[ "$rc" = 2 ]; check $? "unknown argument exits 2"

# 3) THE KEY GUARANTEE: a satisfied --verify short-circuits before any window.
#    'sudo false' would fail loudly if it ever ran, so reaching exit 0 proves the
#    command was never dispatched.
OUT="$(bash "$SCRIPT" --command "sudo false" --verify "true" --label "should not run" 2>&1)"; rc=$?
[ "$rc" = 0 ]; check $? "satisfied --verify exits 0 without running the command"
case "$OUT" in *ALREADY_SATISFIED*) check 0 "announces ALREADY_SATISFIED";; *) check 1 "announces ALREADY_SATISFIED ($OUT)";; esac
case "$OUT" in *osascript*|*Terminal*) check 1 "opened no Terminal window";; *) check 0 "opened no Terminal window";; esac

# 4) the AppleScript is built in Python precisely so quoting cannot break out
grep -q "python3" "$SCRIPT"; check $? "builds the AppleScript via python3, not string concatenation"
grep -q -- "--verify" "$SCRIPT"; check $? "supports --verify (outcome, not assumption)"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
