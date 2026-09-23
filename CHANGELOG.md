# Changelog

All notable changes to the `no-hidden-changes` plugin are documented here. Entries before 1.7.0 are
reconstructed from the git history rather than written at the time.

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
