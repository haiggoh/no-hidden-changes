# Changelog

All notable changes to the `no-hidden-changes` plugin are documented here. Entries before 1.7.0 are
reconstructed from the git history rather than written at the time.

## [1.7.1] — 2026-10-05

### Added — a "deferred" (snooze) state for the first-run reconciliation pass

The reconciliation hook previously had only two states: **not yet reconciled** (re-offers every session)
and **reconciled** (marker written, stays done). This created an unbounded nag when the user legitimately
wanted to defer the pass — dismissing the offer wrote the marker, which silently hid the unfinished
census, while declining to write it meant the banner reappeared every session (and after every `/clear`).

- **New snooze marker files:** `global-snoozed-<host>` and `proj_snoozed_<key>` written by the skill
  when the user dismisses the offer. They record the epoch, surfaces fingerprint (global only), and
  date — a deferred state distinct from "completed".
- **Re-arm logic:** the hook now checks the snooze marker first. A snooze is **valid** (suppresses the
  banner) when the stamped epoch equals the current `RECON_RULES_VERSION` AND (for global) the
  surfaces fingerprint still matches. If the epoch advances OR (global) the automation set changes,
  the snooze expires and the pass re-arms honestly — never silently.
- **Banner while snoozed:** a quiet one-line banner ("census deferred since <date>") replaces the
  full offer, so a deferred pass is **visible, never hidden** — satisfying the plugin's own rule
  against silent state.
- **Skill update:** the skill's reconciliation instructions now document the snooze path — dismissal
  writes the snooze marker instead of the completed marker, and the offer returns only when something
  actually changed.

### Testing

`tests/test_hook.sh` **39 → 48** checks: six new cases covering the snooze/deferred logic:
- Global snooze with matching epoch+surfaces → banner says "deferred", no reconciliation prompt
- Global snooze with stale epoch → re-arms reconciliation
- Global snooze with changed surfaces fingerprint → re-arms reconciliation
- Project snooze with matching epoch → banner says "deferred", no project prompt
- Project snooze with stale epoch → re-arms project reconciliation
All cases mutation-tested by toggling epoch/surfaces and confirming the expected transition.

## [1.7.0] — 2026-09-23

### Added — an ignore rule by EXACT NAME is a hidden change waiting to happen

The plugin already covered branching, staging by path, and never rewriting published history. It said
nothing about the adjacent case where the *absence* of a rule publishes something.

- **New guidance in the skill's "Keep history honest" section and in the SessionStart nudge:** a repo
  that ignores its private overlay by a literal path (`config/config.local.sh`) rather than a pattern
  (`config/*.local.*`) leaves every *later* private file of the same kind publishable by default. This
  is the costly direction of a hidden change — the repo *looks* configured for privacy, and the next
  commit quietly publishes.
- **The check:** run `git check-ignore -v <path>` before the **first** commit of any new private file.
  It prints the rule that matched, so **no output is the warning**. Prefer widening the pattern to
  adding names one at a time.
- Notes explicitly that the remedy afterwards is not a `.gitignore` edit: a published secret needs
  rotation and removal, which is precisely what a force-push does not accomplish — tying this back to
  the existing force-push guidance rather than leaving it as an isolated tip.
- `README.md` gains the fourth reflex-variant bullet, and its "three variants … 1.6.0 puts them" line
  is now version-free, since a prose version number in a README rots with the next release.

### Unchanged on purpose

`RECON_RULES_VERSION` stays at `2`. It gates the one-time *reconciliation pass*, not nudge content —
adding a rule to the nudge does not require every machine to re-run the census. Same precedent as
1.6.0, which added three rules without touching it.

### Testing

`tests/test_hook.sh` 35 → **39** checks: three nudge-content probes (`EXACT NAME`, `check-ignore`,
`no output is the warning`) plus a literal-backtick assertion on the new `` `git check-ignore -v
<path>` `` code span, since prose passed through a double-quoted shell string silently loses a span
while still exiting 0. Each of the three content probes was **mutation-tested** — the nudge wording was
weakened deliberately and each check confirmed to fail, then restored. The stored nudge was also
re-read from disk to confirm the backticks survived and no literal `\u` escape leaked.

## [1.6.0]

Derived-copy edits and history rewrites recognised as hidden changes: edit the source not the installed
cache, branch and stage by path, never force-push or move a published tag.

## [1.4.1] – [1.4.3]

Downstream banner-ordering done-flag; bounded stdin read so a never-closing caller cannot stall
startup; sorted surfaces-fingerprint inputs before hashing.

## [1.x] earlier

The core rule and skill, the first-run reconciliation pass, the read-only automation census, the
per-host marker and the surfaces-hash backstop.
