# Reconciliation re-arm: triage epoch (not release version)

**Date:** 2026-07-07
**Status:** implemented (plugin 1.3.1)

## Problem

`hooks/reconcile-check.sh` decided whether to re-offer the first-run
reconciliation with `stamped_current()`, which required the marker's stored
value to *exactly equal* `RECON_VERSION` — a constant kept in lockstep with the
plugin's release semver. Consequently **any** release that bumped the version
re-armed the reconciliation, even when the rule text (and therefore any possible
triage outcome) had not changed. Observed live: the 1.2.0 → 1.3.0 release
re-triggered a full triage that, predictably, again found zero conflicts.

The reconciliation offer should re-arm only when re-running the triage could
plausibly reach a *different* result — i.e. when the rule itself changed in a
triage-affecting way — and should otherwise accept an existing (possibly older)
marker.

## Design

Decouple the re-arm trigger from the release version by introducing a separate,
slow-moving **triage epoch**.

- **`RECON_RULES_VERSION`** (integer, baseline `1`): bumped *only* when the rule
  text changes such that a previously-clean triage could newly find a
  conflict/duplicate. Cosmetic edits, wording tweaks, and ordinary releases do
  **not** bump it — those bump `plugin.json`'s version instead.
- **`stamped_current()`** accepts a marker (does not re-arm) iff its recorded
  epoch is `>= RECON_RULES_VERSION`. Older-or-equal epochs pass; re-arming
  happens only when the epoch advances past what the marker recorded.
- **Backward compatibility:** markers written before this change hold a dotted
  plugin version (e.g. `1.3.0`). Any dotted value maps to epoch `1`, so existing
  reconciled users are accepted and are *not* forced to re-triage.
- **Fail-safe:** missing, empty, or non-numeric markers re-arm. The pass only
  writes the marker after completing/dismissing, so an un-acted pass re-offers
  next session and cannot be silently lost.

The marker's written value is fully controlled by the hook's prompt strings;
`SKILL.md` defers to "the value the prompt gives you", so the change is localized
to `reconcile-check.sh` (plus tests and the version bump).

## Two clocks

| Version | Changes | Audience | Gates |
|---|---|---|---|
| `plugin.json` version (semver) | every release | humans / marketplace | nothing behavioral |
| `RECON_RULES_VERSION` (epoch) | rarely, on triage-affecting rule change | the hook | whether to re-arm |

Conflating the two was the bug.

## Changes

- `hooks/reconcile-check.sh`: add `RECON_RULES_VERSION`; rewrite
  `stamped_current()` (epoch `>=` compare + legacy-dotted→1 shim + fail-safe);
  prompt strings stamp the epoch.
- `.claude-plugin/plugin.json`: `1.3.0` → `1.3.1` (this ships a behavior change;
  shipping it without a bump would itself violate the rule).
- `tests/test_hook.sh`: track `RECON_RULES_VERSION`; add Case D (legacy dotted
  marker accepted), Case E (stale epoch re-arms), Case F (garbage re-arms).

## Verification

`bash tests/test_hook.sh` → 16/16 pass, covering first-run (global + project),
steady state, legacy-marker acceptance, stale-epoch re-arm, and garbage-marker
fail-safe. `bash -n` clean; `plugin.json` valid at 1.3.1.
