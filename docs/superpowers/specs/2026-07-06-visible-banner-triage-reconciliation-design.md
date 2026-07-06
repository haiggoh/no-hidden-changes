# Design: visible first-run banner + triage-first reconciliation (v1.3.0)

- **Date:** 2026-07-06
- **Status:** Approved (brainstorm), pending implementation plan
- **Target version:** 1.3.0 (minor — new user-facing behavior)
- **Touches:** `hooks/reconcile-check.sh`, `skills/no-hidden-changes/SKILL.md`, `README.md`, `.claude-plugin/plugin.json`

## Context / problem

v1.2.0 shipped first-run reconciliation. In real use three problems surfaced:

1. **No visible confirmation.** A `SessionStart` hook's plain stdout is *added to
   the model's context, not shown to the user* (verified against the Claude Code
   hooks docs). So a fresh installer sees an empty input line and no sign the
   plugin installed or that a reconciliation is pending — then, after their
   (possibly unrelated) first message, the reconciliation appears seemingly from
   nowhere.
2. **Too long-winded.** The `additionalContext` prompt instructs thoroughness and
   front-loads an "inviting offer," so the model produces a large, faintly
   intimidating wall of text — even when there is nothing to reconcile. (In the
   originating session this was amplified by plan mode and an Explanatory output
   style, but the prompt itself is the portion that affects every user.)
3. **A standalone "I can't read your Desktop custom instructions" caveat** reads
   as a scary warning to a new user and does not need to be in every first-run
   message.

## Goals

- A **visible, gentle** first-run banner that confirms the install and
  pre-announces the check, so the post-first-message reconciliation is expected,
  not a surprise.
- **Triage-first, brief** reconciliation: when there is nothing to reconcile
  (the common case), a single-line result — not an explanation.
- Move the Desktop-instructions caveat to the README; keep only a tiny
  contextual note in the rare conflict path.
- Preserve the plugin's **zero runtime-dependency** invariant (no `jq`/`python3`
  required to run the hook).

## Non-goals

- Coloured terminal text. Verified impossible via hooks: `terminalSequence` is
  allowlisted to OSC `0/1/2/9/99/777` + BEL and *explicitly rejects* CSI/SGR
  colour; `systemMessage` styling is the CLI's to decide; hooks cannot write to
  `/dev/tty`. The traffic-light signal is therefore **semantic (emoji), not
  chromatic**.
- Changing the core rule, the red-flag list, or the marker-gating logic.
- Precomputing the conflict result in the hook (impossible — see below).

## Two honest constraints that shape the design

1. **The banner cannot state the result.** The hook runs at session start,
   *before* any model turn; conflict detection is semantic and only the model
   can do it, and the model does not run until the first user message. A banner
   asserting "zero conflicts" would fabricate a result — precisely the
   dishonesty this plugin exists to prevent. So the banner is **neutral**
   ("a check is coming"); the 🟢/🟡 verdict is delivered by the model on its
   first turn (the earliest instant the result exists).
2. **User-visible and model-visible channels are disjoint.** Per the docs:
   `systemMessage` → user sees it, model does not. stdout / `additionalContext`
   → model sees it, user does not. One hook invocation drives both with no
   overlap.

## Design

### First-run experience

1. **Session start** — visible banner via `systemMessage` (persists in
   transcript):
   > 👋 no-hidden-changes active — on your first message I'll do a one-time check
   > of this rule against your existing setup and flag anything that conflicts.
   > Nothing changes without your OK.
2. **First user message** — the model has silently triaged; it leads its reply
   with a one-line result:
   - 🟢 `Checked your existing setup — zero conflicts, nothing to reconcile.`
     then proceeds to the user's actual request; **or**
   - 🟡 `Found N item(s) worth reconciling — brief, below.` followed by the
     concise, neutral, verbatim, default-keep surface + a single informed
     offer.
3. **Every later session** — only the standing nudge (model-only
   `additionalContext`). No banner.

(A per-project first run — entering a brand-new project after the global pass is
done — behaves the same, with the project-scoped banner variant and a check
against that project's `CLAUDE.md`/`AGENTS.md`.)

### `hooks/reconcile-check.sh`

- Switch from plain `printf` to a single **JSON object** on stdout:
  - `hookSpecificOutput.hookEventName`: `"SessionStart"`.
  - `hookSpecificOutput.additionalContext`: the standing nudge, **plus** (first
    run only) the tightened reconciliation prompt.
  - `systemMessage` (first run only): the 👋 banner text.
- **Two first-run branches, both get a banner** (matching the existing script
  structure), with branch-appropriate wording:
  - *Global first run* (no `global-reconciled`): the 👋 "no-hidden-changes active
    — on your first message I'll check this rule against your existing setup…"
    text above.
  - *Per-project first run* (global done, no `proj_<cksum>`): a shorter variant,
    e.g. "👋 no-hidden-changes: new project — on your first message I'll check
    this rule against this project's guidance. Nothing changes without your OK."
- **Marker-gating unchanged**: the script still only *detects and offers*; it
  never writes markers. `stamped_current()` for `global-reconciled` and
  `proj_<cksum>` decides which branch (if any) contributes first-run fields.
- **`RECON_VERSION` bumps to `1.3.0` in lockstep with the plugin version.**
  Existing markers contain `1.2.0`, so `stamped_current()` treats them as stale
  and the first-run reconciliation (new banner + triage flow) re-fires on the
  next session after update — which is exactly the dogfooding path we want to
  exercise. The two versions are kept **coupled** (one concept, not two).
  - *Future reconsideration:* if a real userbase forms, a presentation-only
    change coupled this way would re-offer to everyone — mildly user-hostile.
    At that point, decouple: bump `RECON_VERSION` only when reconciliation
    *semantics* change, not on every plugin bump. Not worth the complexity now
    (sole user).
- **Zero-dependency JSON**: every string is static and known at author time, so
  it is stored **already JSON-escaped** in the script; only the marker *paths*
  (which contain just `/`, `$HOME`, and digits) are interpolated. No `jq`/
  `python3` at runtime. The whole output is one `printf`/heredoc of valid JSON.
- Because JSON output replaces plain stdout, the nudge that today prints as bare
  stdout moves into `additionalContext` (same wording, same model visibility).

### Reconciliation prompt + `SKILL.md` "Reconcile" section

Rewrite to a **triage-first, brevity-capped** procedure:

1. Silently read the readable guidance (global `MEMORY.md` + memory dir,
   `CLAUDE.md`/`AGENTS.md`) and compare to the rule using the existing
   contradiction / duplication / overlap criteria.
2. **Zero findings** → write the marker(s) and emit the single 🟢 line. Do **not**
   explain the feature at length.
3. **Findings** → lead with the 🟡 line, then surface concisely: verbatim quote,
   neutral framing, default-keep, one informed batch offer (unchanged policy,
   tighter prose). Only here, append a *short* contextual half-sentence that
   Desktop custom instructions couldn't be read.
4. Explicit instruction to keep total output brief and non-lecturing.

Remove the standalone mandatory Desktop caveat from the always-shown text.

### `README.md`

- Add a short **"What you'll see on first run"** subsection describing the banner
  and the 🟢/🟡 one-liner.
- Add the **full** caveat: the reconciliation can read memories / `CLAUDE.md` /
  `AGENTS.md` but **not** claude.ai/Desktop custom instructions — review that leg
  manually in Desktop. This is now the caveat's home.

### `.claude-plugin/plugin.json`

- Bump `version` `1.2.0` → `1.3.0` (per the version-bump-on-publish rule; new
  user-facing behavior = minor).

## Verification

- **JSON validity:** pipe the hook's stdout through `python3 -m json.tool` (or
  `jq .`) in the test — must parse. (Test-only; not a runtime dep.)
- **Channel split (fresh session, markers absent):** the 👋 banner is visible to
  the user; the nudge + reconciliation prompt reach the model (not shown to the
  user). Simulate "markers absent" by pointing `HOME`/cwd at a temp dir or
  removing the markers in a throwaway project.
- **Triage-first:** with an aligned setup → single 🟢 line, no wall of text;
  with a seeded conflicting memory → 🟡 line + concise surface + offer.
- **Steady state (markers present):** later sessions emit only the nudge, no
  `systemMessage`, no reconciliation prompt.
- **Regression:** confirm the JSON output coexists with other SessionStart hooks
  (e.g. the user's `joyia ping` telemetry) and does not error the session.

## Rollout notes

- **Re-run is intended.** Bumping `RECON_VERSION` to `1.3.0` supersedes the
  existing `1.2.0` markers, so the reconciliation re-offers once on the first
  session after update (dogfooding). It writes fresh `1.3.0` markers on
  completion and then goes quiet again.
- This spec commit is docs-only and does **not** bump `plugin.json`; the plugin
  and reconciliation version bumps (both to 1.3.0) land with the implementation.
