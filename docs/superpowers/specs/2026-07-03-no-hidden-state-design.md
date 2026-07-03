# `no-hidden-state` — Design Spec

**Date:** 2026-07-03
**Author:** Heiko Brantsch (`haiggoh`)
**Status:** Approved for implementation planning

---

## 1. Purpose

Ship a small, installable artifact that gives Claude a standing behavioral rule:

> When solving a problem, prefer solutions that stay **discoverable, honest, and reversible** and that preserve a tool's native/vanilla UX. Never move or hide state out of the place a tool's own UI reads from if that makes the native UI look empty, absent, or broken — a future user reads it as deceptive or a bug.

The rule originated from a concrete incident (see §8). This project distills the *essence* — not the incident — into something any Claude Code or Claude Desktop user can install.

### Success criteria

1. A Claude Code user can install it in two commands and Claude will thereafter tend to catch itself (or the user) *before* adopting a hidden-state solution.
2. A Claude Desktop / claude.ai user has a clear, correct copy-paste path (no false promise of one-click).
3. The rule fires at the **decision moment** ("about to hide state") with high reliability and stays quiet on benign edits (typos, tests, renames, honest deletions).
4. The artifact itself embodies the rule: discoverable (visible in `/skills`), minimal always-on cost, no hidden mechanisms.

### Non-goals

- No deterministic enforcement (e.g. a PreToolUse hook that blocks edits). The rule is guidance, not a gate — matching how the principle is meant to be applied (flag & discuss, not hard-block).
- No claude.ai one-click install (the platform has no mechanism; copy-paste only).
- Not MCP-specific. MCP-server parking is the canonical *example*, not the scope.

---

## 2. Background & constraints (verified)

Findings from Claude Code / Desktop documentation research (2026-07-03):

- **Claude Code** supports a real plugin marketplace: a repo with `.claude-plugin/marketplace.json` + `plugin.json`, installed via `/plugin marketplace add <owner/repo>` then `/plugin install <plugin>@<marketplace>`. A plugin may bundle skills + hooks together; all components activate together (no per-component picker).
- **Best primitive for a standing principle:** a **SessionStart hook** injecting `additionalContext` is the most reliable "always-on" mechanism, but it imposes a per-session token cost on every user. A **skill** is discoverable and zero-cost-until-invoked but is model-invoked (probabilistic). This project uses **both**, with the hook kept minimal (a one-line pointer, not the full rule) — the same pattern Superpowers uses to make its skills fire reliably.
- **Claude Desktop** has **no** plugin/marketplace mechanism and no `/plugin` command. A standing behavioral instruction there is delivered via **Custom Instructions (copy-paste)**. Therefore a single one-click artifact cannot serve both apps; the repo provides two documented paths.

---

## 3. Architecture

Single Git repository, published as a single-plugin Claude Code marketplace, matching the author's existing `claude-code-desktop-sync` conventions (MIT, `${CLAUDE_PLUGIN_ROOT}`, single-plugin `marketplace.json` named `haiggoh`).

```
no-hidden-state/
├── .claude-plugin/
│   ├── plugin.json              # manifest: name, version, author, license
│   └── marketplace.json         # single-plugin marketplace "haiggoh", source ./
├── skills/
│   └── no-hidden-state/
│       └── SKILL.md             # frontmatter description + full guidance body
├── hooks/
│   └── hooks.json               # SessionStart → emit one-line nudge as additionalContext
├── templates/
│   └── custom-instructions.md   # paste-in snippet for Claude Desktop / claude.ai
├── README.md                    # dual install path + the "why"
└── LICENSE                      # MIT, Heiko Brantsch
```

### Component responsibilities

| Component | Does | Depends on |
|-----------|------|------------|
| `SKILL.md` | Carries the full principle. Its frontmatter `description` is the trigger surface; its body is the guidance Claude reads once invoked. | Nothing |
| `hooks/hooks.json` | On SessionStart, prints a one-line pointer to stdout → Claude Code injects it as `additionalContext`, nudging Claude to consult the skill. | The skill existing (references it by name) |
| `templates/custom-instructions.md` | Equivalent rule text for platforms without plugin support. Standalone. | Nothing |
| `README.md` | Explains both install paths, the origin, and the honest trade-offs. | — |
| manifests | Make the repo installable as a marketplace plugin. | Claude Code plugin loader |

---

## 4. Component detail

### 4.1 `SKILL.md`

Frontmatter:
- `name: no-hidden-state`
- `description:` trimmed to ~70–90 words (best-practice length; the nudge hook shares the triggering load). Keeps: the decision-moment trigger, the verb list (disable/hide/park/move/rename/relocate state; side-channel over native toggle), the "will a future user see accurate native state?" check, and the benign carve-out (typos, tests, cosmetic refactors, renames, honest deletions).

Body sections (guidance loaded only on invocation):
1. The core principle: discoverability & honesty over cleverness
2. Red-flag signatures (empty native UI, `_disabled`/`_backup` buckets, shadow files, unread side-channel flags)
3. The one check: what will a future user see in the tool's own UI?
4. Prefer native mechanisms: per-item toggles, documented settings, feature flags
5. When a hidden workaround is unavoidable: make invisibility loud and self-explanatory in place
6. The canonical anti-pattern: MCP servers moved to `mcpServers_disabled` → empty `/mcp` menu
7. When NOT to apply: typos, tests, cosmetic renames, honest deletions

### 4.2 `hooks/hooks.json`

- `SessionStart` matcher `startup` (and `resume`/`clear` as appropriate), one hook of `type: command`.
- Command echoes a single-line nudge to stdout (portable `echo`/`printf`, no interpreter dependency), which Claude Code surfaces as `additionalContext`.
- Nudge text (from the optimization run): instructs Claude to STOP and consult `no-hidden-state` before adopting any fix that disables/hides/parks/removes/relocates state or reaches for a custom side-channel over a native control; treat "the tool's own UI won't show it anymore" as a red flag.
- **Manifest caveat** (learned on `claude-code-desktop-sync`): do NOT reference `hooks/hooks.json` from `plugin.json`'s `hooks` key — Claude Code auto-loads the conventional path, and double-referencing causes a "Duplicate hooks file" install error. `hooks/hooks.json` loads automatically from the plugin root.

### 4.3 `templates/custom-instructions.md`

Plain prose version of the rule (no skill/hook machinery) for pasting into Claude Desktop / claude.ai Custom Instructions. Self-contained; states the principle, the red flags, and the one check.

### 4.4 Manifests

- `plugin.json`: `name: no-hidden-state`, `version: 1.0.0`, `description`, `author` (Heiko Brantsch), `license: MIT`. No `hooks` key (see §4.2).
- `marketplace.json`: single-plugin marketplace named `haiggoh`, plugin source `./`.

---

## 5. Data / control flow

**Code install:** user runs `/plugin marketplace add haiggoh/no-hidden-state` → `/plugin install no-hidden-state@haiggoh`. On next session: hook fires at SessionStart → one-line nudge enters context → when a task approaches a hide-state decision, Claude invokes the skill → reads full guidance → steers toward the native/visible option or flags the trade-off.

**Desktop/web install:** user copies `templates/custom-instructions.md` into Custom Instructions → rule is present in every conversation as standing instruction.

---

## 6. Error handling & edge cases

- **Duplicate-hooks install error:** avoided by not referencing the standard hooks path in the manifest (§4.2).
- **Over-triggering:** mitigated by the explicit benign carve-out in the description and the "one check" discriminator (honest deletion = quiet; disguised park = fires).
- **Under-triggering:** mitigated by the always-on nudge hook reinforcing the skill.
- **Cross-platform hook portability:** the nudge command uses a plain shell `echo`/`printf` with no interpreter or path dependency, so it works without Python/Node.
- **Description bloat:** capped at ~70–90 words to respect the always-on cost of all skill descriptions loading each session.

---

## 7. Testing / verification

- **Manifest validity:** `plugin.json` and `marketplace.json` parse as valid JSON; required keys present.
- **Hook shape:** `hooks/hooks.json` matches the documented SessionStart schema; command emits exactly the one-line nudge.
- **Local install smoke test:** verify no "Duplicate hooks" error and the skill appears in `/skills` (performed after publish / in a fresh session).
- **Trigger sanity:** the description+nudge were adversarially scored (5 candidate strategies × 3 judges × 12 labeled scenarios). Caveat: all candidates scored 1.00 P/R, meaning the eval did not *discriminate* — treat as "no obvious hole," not proof of optimality. The shipped wording unions the strongest triggers and keeps the shared benign carve-out.

---

## 8. Origin (for the README, not the shipped rule)

The rule crystallized from an MCP cost-management episode: to cut per-turn token cost, MCP servers were "parked" by moving them out of the `mcpServers` config key into a custom `mcpServers_disabled` key. This worked but made the native `/mcp` menu show up **empty** — which a returning user could reasonably read as deceptive or broken. The discoverable alternative (keep servers registered/visible, use the native per-session disable, rely on tool-search deferral for cost) preserved the vanilla UX. The generalized lesson became this rule.

---

## 9. Build phases

1. **Local build (this session):** create all files under `~/ClaudeWorkspace/no-hidden-state/`, `git init`, validate JSON manifests, first commit.
2. **Publish (after session restart, when the GitHub MCP loads):** create the public repo `haiggoh/no-hidden-state`, push via MCP `push_files` (token cannot be materialized for plain `git push`, per prior experience), verify anonymously with `git fetch` + `git diff`.
3. **Version discipline:** bump `plugin.json` `version` on any functional change (patch for fixes, minor for features).
