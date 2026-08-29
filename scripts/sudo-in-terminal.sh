#!/opt/homebrew/bin/bash
# Runs a command needing an interactive password in a REAL Terminal window, then
# waits for it to take effect.
#
#   sudo-in-terminal.sh --command "<cmd>" [--verify "<shell test>"]
#                       [--timeout SECONDS] [--label "what this does"]
#
# Why this exists: sudo needs a TTY to prompt for a password. Claude Code's Bash
# tool has none, and neither does the `!` prefix — both fail with "a terminal is
# required to read the password". Activating Privileges does NOT help: it grants
# admin group membership, but sudo still wants the password. Previously the only
# option was to ask the user to retype the line somewhere else.
#
# Instead this opens Terminal.app with the command already entered and running, so
# the user only types their password and presses return. With --verify it then
# polls for the OUTCOME rather than reporting success just because a window
# opened — a cancelled or mistyped prompt must not look like it worked.
#
# Example:
#   sudo-in-terminal.sh \
#     --command "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" \
#     --verify  '[ "$(xcode-select -p)" = "/Applications/Xcode.app/Contents/Developer" ]' \
#     --label   "point xcode-select at full Xcode"
set -uo pipefail

COMMAND=""
VERIFY=""
TIMEOUT=300
LABEL=""

while [ $# -gt 0 ]; do
	case "$1" in
		--command) COMMAND="${2:-}"; shift 2 ;;
		--verify)  VERIFY="${2:-}";  shift 2 ;;
		--timeout) TIMEOUT="${2:-300}"; shift 2 ;;
		--label)   LABEL="${2:-}";   shift 2 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

if [ -z "$COMMAND" ]; then
	echo "error: --command is required" >&2
	exit 2
fi

# If the desired state already holds, do not interrupt the user at all.
if [ -n "$VERIFY" ] && eval "$VERIFY" >/dev/null 2>&1; then
	echo "ALREADY_SATISFIED: nothing to do"
	exit 0
fi

# Build the AppleScript in Python so quotes and backslashes in the command cannot
# break out of the string literal.
SCRIPT=$(COMMAND="$COMMAND" LABEL="$LABEL" python3 <<'PY'
import os

command = os.environ["COMMAND"]
label = os.environ.get("LABEL", "")

banner = "Claude needs your password"
if label:
    banner += f" to {label}"

# echo a short explanation first so the window is self-describing rather than a
# bare password prompt appearing out of nowhere.
full = f"clear; echo '=== {banner} ==='; echo; {command}"


def applescript_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


print(
    'tell application "Terminal"\n'
    "  activate\n"
    f'  do script "{applescript_quote(full)}"\n'
    "end tell"
)
PY
)

echo "opening Terminal window with the command pre-entered…"
osascript -e "$SCRIPT" >/dev/null || {
	echo "error: could not drive Terminal.app (Automation permission?)" >&2
	exit 1
}

if [ -z "$VERIFY" ]; then
	echo "OPENED: no --verify given, cannot confirm completion"
	exit 0
fi

echo "waiting up to ${TIMEOUT}s for the change to take effect…"
elapsed=0
while [ "$elapsed" -lt "$TIMEOUT" ]; do
	if eval "$VERIFY" >/dev/null 2>&1; then
		echo "VERIFIED after ${elapsed}s"
		exit 0
	fi
	sleep 2
	elapsed=$((elapsed + 2))
done

# Timeout is not proof of failure — the user may have walked away. Say which.
echo "NOT_VERIFIED: still not in the expected state after ${TIMEOUT}s" >&2
exit 1
