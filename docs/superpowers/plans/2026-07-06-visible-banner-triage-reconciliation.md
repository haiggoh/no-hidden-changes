# Visible Banner + Triage-First Reconciliation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make first-run reconciliation announce itself with a gentle, user-visible banner and reply with a one-line 🟢/🟡 result instead of a wall of text.

**Architecture:** The SessionStart hook (`reconcile-check.sh`) switches from plain-text stdout to a single JSON object, using the two disjoint hook channels — `systemMessage` (user-visible banner) and `hookSpecificOutput.additionalContext` (model-only nudge + reconciliation prompt). The reconciliation prompt and the skill are reworded to triage silently first. Everything else (marker gating, the rule itself) is unchanged.

**Tech Stack:** Bash (target: macOS system bash 3.2), JSON via a pure-bash escaper (no runtime `jq`/`python3`), Claude Code plugin hooks.

## Global Constraints

- **Bash 3.2 compatible** — no bash-4+ features (no `${var^^}`, associative arrays, `mapfile`). Parameter-expansion substitution and `$'\n'` ANSI-C quoting are OK (verified).
- **Zero runtime dependencies** — the hook must run with bash alone. `jq`/`python3` may be used **only** by the test.
- **Coupled versions** — `.claude-plugin/plugin.json` `version` and the script's `RECON_VERSION` both become exactly `1.3.0`.
- **Two disjoint channels** — `systemMessage` → user only; `additionalContext` → model only. Output is exactly one JSON object.
- **Marker gating unchanged** — the hook only detects + offers; it never writes markers.
- **Banner is neutral** — it announces the check; it must not claim a result. The 🟢/🟡 verdict comes only from the model post-input.
- **Commit trailer** — every commit ends with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Source of truth: `docs/superpowers/specs/2026-07-06-visible-banner-triage-reconciliation-design.md`.

## File Structure

- `hooks/reconcile-check.sh` — **rewrite**: JSON output, `json_escape()`, banner + triage prompt variables, two first-run branches.
- `tests/test_hook.sh` — **create**: framework-free test (requires `jq`), covers the 3 output modes.
- `skills/no-hidden-changes/SKILL.md` — **modify**: rewrite the "Reconcile with the user's existing guidance" section (triage-first, brief, Desktop caveat demoted).
- `README.md` — **modify**: "What you'll see on first run" + the Desktop-instructions caveat (its new home).
- `.claude-plugin/plugin.json` — **modify**: `version` → `1.3.0`.
- `hooks/hooks.json` — **unchanged** (still `bash "${CLAUDE_PLUGIN_ROOT}/hooks/reconcile-check.sh"`); no edit.

---

### Task 1: Hook emits JSON (banner + triage prompt)

**Files:**
- Modify (full rewrite): `hooks/reconcile-check.sh`
- Create: `tests/test_hook.sh`

**Interfaces:**
- Produces: a single JSON object on stdout. Shape: `{"systemMessage"?: string, "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": string}}`. `systemMessage` present only on a first-run branch.
- Consumes: env `HOME` (marker dir root) and `PWD` (per-project key), exactly as today.

- [ ] **Step 1: Write the failing test** — create `tests/test_hook.sh`:

```bash
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
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `bash tests/test_hook.sh`
Expected: FAIL — the current hook emits plain text, so `jq . "$OUT"` fails ("valid JSON" FAIL) and field extractions are empty.

- [ ] **Step 3: Rewrite `hooks/reconcile-check.sh`** to this exact content:

```bash
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

RECON_VERSION='1.2.0'
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
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `bash tests/test_hook.sh`
Expected: all checks PASS, final line `PASS=9 FAIL=0`, exit 0.

- [ ] **Step 5: Manually confirm valid JSON in each mode** (belt-and-suspenders)

Run: `HOME="$(mktemp -d)" bash hooks/reconcile-check.sh | jq .`
Expected: pretty-printed JSON with `systemMessage` (starts 👋) and `hookSpecificOutput.additionalContext` (nudge + first-run reconciliation prompt).

- [ ] **Step 6: Commit**

```bash
git add hooks/reconcile-check.sh tests/test_hook.sh
git commit -m "feat(hook): emit JSON with user-visible banner + triage-first prompt

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Rewrite the SKILL.md reconcile section

**Files:**
- Modify: `skills/no-hidden-changes/SKILL.md` (the section `## Reconcile with the user's existing guidance`)

**Interfaces:**
- Consumes: nothing. Must stay **wording-consistent** with Task 1's `COMMON`/prompts (triage-first, 🟢/🟡, brief, Desktop caveat only in the conflict path).

- [ ] **Step 1: Replace the entire `## Reconcile with the user's existing guidance` section** (from that heading up to, but not including, the next `## Canonical anti-pattern` heading) with:

```markdown
## Reconcile with the user's existing guidance

Almost everyone installs this rule *on top of* an existing setup. Old standing
guidance can **contradict**, **duplicate**, or **overlap** it — and letting that
sit unsurfaced is itself a hidden change. So on the first session after install
(a SessionStart banner announces it), once per new project, and reactively when
the rule is about to apply, reconcile it with the user's guidance — **triage
first, and be brief.**

**Triage first — before saying anything.** Silently read the readable guidance
and compare it to the rule:

- **Sources you can read (Claude Code):** global auto-memory (`~/.claude`
  `MEMORY.md` + memory dir) and `CLAUDE.md` / `AGENTS.md`. You **cannot** read
  claude.ai/Desktop custom instructions.
- **Nothing to reconcile** (the common case): write the marker(s) and reply with
  a single line led by 🟢 — *"🟢 Checked your existing setup — zero conflicts,
  nothing to reconcile."* — then go straight to the user's actual request. Do
  **not** explain the feature at length.
- **Something to reconcile:** lead with one 🟡 line — *"🟡 Found N item(s) worth
  reconciling — below."* — then surface it concisely (below). Only in this path,
  add a short note that Desktop custom instructions couldn't be read.

**Surfacing a finding — surface first, change only after an informed, per-item
choice; never silently, never a blind "apply all":**

- **Contradiction** — quote the conflicting instruction **verbatim** and explain
  the clash **neutrally**: both it and the rule as possibly-intentional (no "old
  one is wrong/regretted" framing). Recommend the transparency-improving change,
  but **default to keeping** the existing instruction unless the user actively
  chooses to change it.
- **Duplication** — point out the near-identical rule; propose one canonical
  source. If the near-duplicate is *this plugin's own shipped text* (pasted
  template / reinstall), keep the user's on-disk copy (it survives uninstall).
- **Overlap** — state how you'll reconcile and confirm, per item.

**One informed batch (opt-in):** show **all** proposed before/after diffs
together for a single approval — the user may take the set, a subset, or none.
Review-then-approve, not blind-apply.

**Persisting a resolution:**
- Personal auto-memory / *uncommitted* `CLAUDE.md` → edit in place after
  confirmation; treat the `MEMORY.md` index entry and its linked note as one unit.
- *Committed* `CLAUDE.md`, and **always** `AGENTS.md` (other tools read it) →
  propose a diff to commit; never auto-commit, and flag `AGENTS.md`'s cross-tool reach.
- **Record declines** as durable notes ("kept X over the rule on <date>") and
  respect them — never re-nag a settled decision.

**The once-only marker:** the SessionStart prompt gives you the marker path(s)
and the reconciliation version. Write the version into the marker **only after
the pass completes or the user dismisses it** — never before. An un-acted pass
then simply re-offers next session, so it cannot be lost.
```

- [ ] **Step 2: Verify the standalone Desktop caveat is gone from the always-shown text**

Run: `grep -n "cannot" skills/no-hidden-changes/SKILL.md`
Expected: the only "cannot read claude.ai/Desktop" mention is inside the triage "Sources" bullet (a limitation note), **not** a standalone mandatory warning paragraph.

- [ ] **Step 3: Verify wording consistency with the hook prompt**

Run: `grep -c "TRIAGE\|🟢\|🟡" skills/no-hidden-changes/SKILL.md`
Expected: ≥ 3 (triage-first + both semaphores present, matching Task 1's `COMMON`).

- [ ] **Step 4: Commit**

```bash
git add skills/no-hidden-changes/SKILL.md
git commit -m "docs(skill): triage-first, brief reconciliation; demote Desktop caveat

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Update the README

**Files:**
- Modify: `README.md` (the `**First-run reconciliation (Claude Code):**` paragraph, currently ~lines 41-47)

- [ ] **Step 1: Replace that paragraph** with:

```markdown
**First-run reconciliation (Claude Code):** the first session after you install — and once
per new project — the plugin does a one-time check of this rule against your *existing*
memories / `CLAUDE.md` / `AGENTS.md`.

What you'll see:
- **At session start**, a short banner — *👋 no-hidden-changes active — on your first message
  I'll check this rule against your existing setup…* It announces the check; it can't report a
  result yet (nothing has been read at that point).
- **After your first message**, a one-line result: 🟢 *zero conflicts, nothing to reconcile*
  and Claude continues with your request — or 🟡 *found something*, followed by a concise,
  per-item, **verbatim, default-keep** surface and a single informed offer. Nothing is
  rewritten without your confirmation; files other tools read (e.g. `AGENTS.md`) are offered
  as diffs.

**What it cannot see:** the reconciliation reads your Claude Code memories / `CLAUDE.md` /
`AGENTS.md`, but it **cannot** read your claude.ai / Claude Desktop **Custom Instructions** —
those live server-side, out of a session's reach. If you keep this rule (or one that conflicts
with it) there, review that leg manually in Desktop.

Note that plugin hooks activate on the **next** session, so **start a fresh session after
installing** for the pass to run.
```

- [ ] **Step 2: Verify**

Run: `grep -n "Custom Instructions\|👋\|🟢" README.md`
Expected: the Desktop Custom-Instructions caveat and both banner/result cues are present.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): document first-run banner/result + Desktop-instructions caveat

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Bump versions to 1.3.0 (coupled)

**Files:**
- Modify: `.claude-plugin/plugin.json` (`version`)
- Modify: `hooks/reconcile-check.sh` (`RECON_VERSION`)

**Interfaces:**
- Consumes: the version-agnostic test from Task 1 (reads `RECON_VERSION` from the script, so it stays green across the bump).

- [ ] **Step 1: Bump `plugin.json`** — change `"version": "1.2.0"` to `"version": "1.3.0"`.

- [ ] **Step 2: Bump the script** — change `RECON_VERSION='1.2.0'` to `RECON_VERSION='1.3.0'` in `hooks/reconcile-check.sh`.

- [ ] **Step 3: Verify both are 1.3.0**

Run: `grep -H '1.3.0' .claude-plugin/plugin.json hooks/reconcile-check.sh`
Expected: one match in each file.

- [ ] **Step 4: Re-run the test (must still pass)**

Run: `bash tests/test_hook.sh`
Expected: `PASS=9 FAIL=0` (the test read `RECON_VERSION` from the script, so the bump doesn't break it).

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json hooks/reconcile-check.sh
git commit -m "chore: bump plugin + reconciliation version to 1.3.0

Coupled bump: RECON_VERSION supersedes existing 1.2.0 markers so the new
first-run flow re-runs once on update (intended dogfooding).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Publish & dogfood

**Files:** none (git + manual verification)

- [ ] **Step 1: Push**

```bash
git push origin main
```
Expected: fast-forward push; `git rev-list --left-right --count origin/main...HEAD` → `0  0`.

- [ ] **Step 2: Update the installed plugin** (in the user's Claude Code, interactive)

Run in a Claude Code prompt: `/plugin update` (or `/plugin marketplace update haiggoh`)
Expected: cache updates to `.../no-hidden-changes/1.3.0/`.

- [ ] **Step 3: Dogfood in a fresh session** (manual observation)

Start a **new** session (hooks load next session). Expected sequence:
1. A visible 👋 banner at session start (the `1.2.0` markers are now stale vs `1.3.0`, so the global first-run fires).
2. On your first message, a single 🟢 line (your setup already reconciled clean at 1.2.0 → still clean) and Claude proceeds — **no wall of text**.
3. `cat ~/.claude/.no-hidden-changes/global-reconciled` → `1.3.0` afterward.

- [ ] **Step 4: Confirm steady state**

Start another new session. Expected: no banner; only the standing nudge reaches the model.

---

## Self-Review

**1. Spec coverage:**
- Visible banner (`systemMessage`) → Task 1. ✅
- Triage-first + 🟢/🟡 brief result → Task 1 (`COMMON`) + Task 2 (skill). ✅
- Desktop caveat → README, demoted in skill → Task 2 + Task 3. ✅
- Zero runtime dependency (pure-bash escaper) → Task 1. ✅
- Coupled 1.3.0 bump + intended re-run → Task 4 + Task 5 dogfood. ✅
- Two first-run branches both get a (variant) banner → Task 1 + test Case B. ✅
- Honest constraints (neutral banner, no colour) → encoded in banner wording (Task 1) and README (Task 3). ✅

**2. Placeholder scan:** No TBD/TODO. `N item(s)` and `<date>` are runtime-filled by the model at reconciliation time, not plan placeholders. Full file content given for the rewrite; exact replacement blocks for edits. ✅

**3. Type/name consistency:** `RECON_VERSION`, `json_escape`, `stamped_current`, `GLOBAL`/`PROJ`, `context`/`banner` used identically across Task 1 and the test. Test greps ("first-run reconciliation", "TRIAGE-FIRST", "before any change that disables", "active", "new project") match the exact strings authored in Task 1. Version-bump task keeps the test green by construction (test reads the version from the script). ✅
