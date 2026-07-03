# no-hidden-changes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `no-hidden-changes` Claude Code plugin repo locally — a skill + minimal nudge hook that steers Claude toward visible, honest, reversible changes — plus a copy-paste path for Claude Desktop / claude.ai.

**Architecture:** A single Git repo published as a single-plugin Claude Code marketplace. A `SKILL.md` carries the full principle (loaded on invocation); a one-line `SessionStart` hook injects a pointer every session to raise trigger reliability; a `templates/custom-instructions.md` serves platforms without plugin support. No runtime code — deliverables are manifests, a skill, a hook, docs.

**Tech Stack:** Claude Code plugin format (`.claude-plugin/`), JSON manifests, Markdown + YAML frontmatter, POSIX shell (`printf`) for the hook. Validation via `jq` and `python3` (YAML/word-count checks).

## Global Constraints

- Plugin/skill/repo name: `no-hidden-changes` (exact, everywhere).
- Marketplace name: `haiggoh`; plugin source `./`.
- Author: `Heiko Brantsch`; License: `MIT`; GitHub owner: `haiggoh`.
- Version: start `1.0.0`; bump `plugin.json` `version` on any later functional change (patch=fix, minor=feature).
- `plugin.json` MUST NOT contain a `hooks` key — Claude Code auto-loads `hooks/hooks.json` from the plugin root; referencing it also causes a "Duplicate hooks file" install error.
- Skill `description`: target 70–90 words; keep decision-moment trigger + verb list + the "future user sees accurate native state?" check + benign carve-out.
- Hook command must use only POSIX shell with no interpreter dependency (no Python/Node), no inner double-quotes or apostrophes (avoid JSON/shell escaping hazards).
- Repo already exists at `~/ClaudeWorkspace/no-hidden-changes/` with the committed design spec. All paths below are relative to that directory.
- Publishing to GitHub is OUT OF SCOPE for this plan (requires the GitHub MCP, which loads only after a session restart). This plan ends at a validated local repo.

---

### Task 1: Plugin manifests

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`

**Interfaces:**
- Produces: marketplace name `haiggoh` and plugin name `no-hidden-changes` (source `./`) that the install commands and README depend on.

- [ ] **Step 1: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "no-hidden-changes",
  "version": "1.0.0",
  "description": "Steer Claude toward visible, honest, reversible changes and away from hidden-state workarounds that make a tool's own UI look empty, absent, or deceptive.",
  "author": { "name": "Heiko Brantsch" },
  "homepage": "https://github.com/haiggoh/no-hidden-changes",
  "license": "MIT",
  "keywords": ["skill", "hook", "behavior", "transparency", "ux", "config", "safety"]
}
```

- [ ] **Step 2: Create `.claude-plugin/marketplace.json`**

```json
{
  "name": "haiggoh",
  "owner": { "name": "Heiko Brantsch", "url": "https://github.com/haiggoh" },
  "plugins": [
    {
      "name": "no-hidden-changes",
      "source": "./",
      "description": "Prefer visible, honest, reversible changes over hidden-state workarounds."
    }
  ]
}
```

- [ ] **Step 3: Validate both files are valid JSON with required keys**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
jq -e '.name=="no-hidden-changes" and .version=="1.0.0" and .license=="MIT" and (has("hooks")|not)' .claude-plugin/plugin.json
jq -e '.name=="haiggoh" and (.plugins[0].name=="no-hidden-changes") and (.plugins[0].source=="./")' .claude-plugin/marketplace.json
```
Expected: each prints `true` and exits 0. (The `has("hooks")|not` check enforces the no-`hooks`-key constraint.)

- [ ] **Step 4: Commit**

```bash
cd ~/ClaudeWorkspace/no-hidden-changes
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git -c user.name="Heiko Brantsch" -c user.email="noreply@haiggoh.dev" commit -m "feat: add plugin and marketplace manifests"
```

---

### Task 2: The skill (`SKILL.md`)

**Files:**
- Create: `skills/no-hidden-changes/SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: skill name `no-hidden-changes` referenced by the nudge hook (Task 3) and README (Task 5).

- [ ] **Step 1: Create `skills/no-hidden-changes/SKILL.md`**

```markdown
---
name: no-hidden-changes
description: Use before adopting or proposing any change — a fix, workaround, config edit, refactor, or file/data move — that disables, hides, parks, removes, or relocates something, or that reaches for a custom side-channel (a `_disabled`/`_backup` key, a shadow file, an unread flag) instead of a tool's built-in toggle, menu, or setting. The test: will a future user opening the tool's OWN native UI see accurate, non-deceptive state, or will it look empty, absent, or broken? Prefer the native, visible path; if hidden state is unavoidable, flag it loudly and make it self-explanatory in place. Do not trigger on benign edits — typo fixes, tests, cosmetic refactors, renames-for-clarity, or genuine intentional deletions where nothing is being hidden.
---

# No Hidden Changes

## The core principle

Prefer solutions that stay **discoverable, honest, and reversible** and that preserve a tool's native, vanilla UX. A clever or cheaper workaround that a future user (or session) can't see is not cheaper — the hidden cost lands later, as confusion or a false impression that something is broken.

## Red-flag signatures

Stop and apply this skill the moment a solution involves any of these:

- Moving, renaming, or commenting-out state/config out of the key, table, file, or directory a tool's own UI, menu, dashboard, or listing reads from.
- A custom side-channel: a `_disabled` / `_backup` / `_old` bucket, a shadow file, or a flag the native UI never reads.
- Suppressing, blanking, or fake-emptying a native view so it shows less than the truth.
- Choosing a bespoke hack over a documented native mechanism (per-item enable/disable, standard settings, a menu, a feature flag).

## The one check

> Will a future user or session, opening the tool's OWN native UI, see accurate, non-broken, self-explanatory state?

If the honest answer is "no — it'll look empty, absent, or wrong," the solution is hiding state. Change course or flag it loudly.

## Prefer native mechanisms

Reach first for what the tool ships with: per-item toggles, documented settings, standard menus, feature flags. These keep the change visible where users expect to find it, and reversible by someone who has never heard of your workaround. A native path that costs a little more is usually worth it.

## When hidden state is truly unavoidable

Sometimes there is no native mechanism. Then treat invisibility as a real cost, not a neutral: surface it loudly, document it in the most discoverable place available, and prefer a form that explains itself in place (a clearly-named marker, an in-UI note) over a silent side-channel. Optimize for the person who will find this later without knowing the trick exists.

## Canonical anti-pattern

Disabling MCP servers by moving them out of the `mcpServers` config key into a custom `mcpServers_disabled` key. It works — but the native `/mcp` menu then shows up **empty**, which a returning user reads as deceptive or broken. The discoverable alternative: keep the servers registered/visible and use the native per-session disable, accepting the small, honest cost.

## When NOT to apply

This skill is not a tax on ordinary work. Stay quiet for typo fixes, adding tests, cosmetic refactors, renames-for-clarity, and genuine intentional deletions — anything where nothing is being hidden, relocated, or made to fake an empty or broken native view.
```

- [ ] **Step 2: Validate frontmatter parses and has name + description**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
python3 - <<'PY'
import re, sys
text = open("skills/no-hidden-changes/SKILL.md", encoding="utf-8").read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert m, "no frontmatter block"
fm = m.group(1)
assert re.search(r"^name:\s*no-hidden-changes\s*$", fm, re.M), "name missing/wrong"
desc = re.search(r"^description:\s*(.+)$", fm, re.M)
assert desc, "description missing"
print("frontmatter OK")
PY
```
Expected: prints `frontmatter OK`, exits 0.

- [ ] **Step 3: Validate description word count is in the 70–90 target band**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
python3 - <<'PY'
import re
fm = re.match(r"^---\n(.*?)\n---\n", open("skills/no-hidden-changes/SKILL.md", encoding="utf-8").read(), re.S).group(1)
desc = re.search(r"^description:\s*(.+)$", fm, re.M).group(1)
n = len(desc.split())
print("description words:", n)
assert 60 <= n <= 100, f"out of band: {n}"
print("word count OK")
PY
```
Expected: prints the word count and `word count OK`. (Band widened to 60–100 to allow minor edits; target remains ~70–90.)

- [ ] **Step 4: Commit**

```bash
cd ~/ClaudeWorkspace/no-hidden-changes
git add skills/no-hidden-changes/SKILL.md
git -c user.name="Heiko Brantsch" -c user.email="noreply@haiggoh.dev" commit -m "feat: add no-hidden-changes skill"
```

---

### Task 3: The nudge hook

**Files:**
- Create: `hooks/hooks.json`

**Interfaces:**
- Consumes: skill name `no-hidden-changes` (from Task 2).
- Produces: a SessionStart hook that emits a one-line pointer to stdout (Claude Code surfaces stdout as `additionalContext`).

- [ ] **Step 1: Create `hooks/hooks.json`**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "printf '%s' 'no-hidden-changes: before any change that disables, hides, parks, removes, or relocates state or config — or that reaches for a custom side-channel instead of a native toggle or menu — STOP and consult the no-hidden-changes skill first. Treat a tool no longer showing something in its own UI as a red flag, not a detail.'"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON shape matches the SessionStart hook schema**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
jq -e '.hooks.SessionStart[0].matcher=="startup" and .hooks.SessionStart[0].hooks[0].type=="command" and (.hooks.SessionStart[0].hooks[0].command|test("no-hidden-changes skill"))' hooks/hooks.json
```
Expected: prints `true`, exits 0.

- [ ] **Step 3: Verify the hook command runs and emits the one-line nudge**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
sh -c "$(jq -r '.hooks.SessionStart[0].hooks[0].command' hooks/hooks.json)"; echo
```
Expected: prints the single-line nudge starting `no-hidden-changes: before any change...` and no shell error (exit 0). The trailing `echo` just adds a newline for readability.

- [ ] **Step 4: Re-confirm `plugin.json` has no `hooks` key (duplicate-load guard)**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
jq -e 'has("hooks")|not' .claude-plugin/plugin.json
```
Expected: prints `true`, exits 0.

- [ ] **Step 5: Commit**

```bash
cd ~/ClaudeWorkspace/no-hidden-changes
git add hooks/hooks.json
git -c user.name="Heiko Brantsch" -c user.email="noreply@haiggoh.dev" commit -m "feat: add SessionStart nudge hook"
```

---

### Task 4: Desktop / claude.ai copy-paste template

**Files:**
- Create: `templates/custom-instructions.md`

**Interfaces:**
- Consumes: nothing (standalone prose; no skill/hook machinery).
- Produces: a self-contained rule block the README (Task 5) links to.

- [ ] **Step 1: Create `templates/custom-instructions.md`**

```markdown
# no-hidden-changes — Custom Instructions (Claude Desktop / claude.ai)

Claude Desktop and claude.ai have no plugin system, so paste the block below into
**Settings → Custom Instructions** (or a Project's instructions). It delivers the
same rule the Claude Code plugin does, as a standing instruction.

---

When solving a problem, prefer changes that stay visible, honest, and reversible,
and that preserve a tool's native UX. Before adopting or proposing any change that
disables, hides, parks, removes, or relocates state or config — or that reaches for
a custom side-channel (a `_disabled`/`_backup` key, a shadow file, an unread flag)
instead of a built-in toggle, menu, or setting — stop and ask: will a future user
opening the tool's OWN native UI see accurate, non-deceptive state, or will it look
empty, absent, or broken? If the latter, prefer the native, visible path; if hidden
state is truly unavoidable, flag it loudly and make it self-explanatory in place.
Do not apply this to benign edits — typos, tests, cosmetic refactors, renames, or
honest deletions where nothing is being hidden.

---
```

- [ ] **Step 2: Validate the file exists and contains the "one check" sentence**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
grep -q "native UI see accurate, non-deceptive state" templates/custom-instructions.md && echo "template OK"
```
Expected: prints `template OK`, exits 0.

- [ ] **Step 3: Commit**

```bash
cd ~/ClaudeWorkspace/no-hidden-changes
git add templates/custom-instructions.md
git -c user.name="Heiko Brantsch" -c user.email="noreply@haiggoh.dev" commit -m "docs: add Desktop/web custom-instructions template"
```

---

### Task 5: README and LICENSE

**Files:**
- Create: `README.md`
- Create: `LICENSE`

**Interfaces:**
- Consumes: install identifiers from Tasks 1–4 (marketplace `haiggoh`, plugin `no-hidden-changes`, template path).

- [ ] **Step 1: Create `README.md`**

````markdown
# no-hidden-changes

A tiny Claude behavior rule: **prefer visible, honest, reversible changes over
hidden-state workarounds.** When a fix would move or hide state where a tool's own
UI can't show it — leaving a native menu empty or a dashboard lying — this steers
Claude to the discoverable, native path instead, or to flag the trade-off out loud.

It ships two ways: a one-click **Claude Code plugin** (a skill + a one-line
session nudge), and a copy-paste **Custom Instructions** block for Claude Desktop
and claude.ai (which have no plugin system).

## Why

The rule came from a real moment. To cut token cost, some MCP servers were
"parked" by moving them out of the `mcpServers` config key into a custom
`mcpServers_disabled` key. It worked — but the native `/mcp` menu then showed up
**empty**, which reads as deceptive or broken to anyone coming back later. The
honest alternative (keep them registered/visible, use the native per-session
disable) preserved the vanilla UX. Generalized, that lesson is this project:
don't make a tool's own UI lie about its state.

## Install — Claude Code (one-click)

```
/plugin marketplace add haiggoh/no-hidden-changes
/plugin install no-hidden-changes@haiggoh
```

You get:
- a `no-hidden-changes` **skill** (visible in `/skills`, zero token cost until
  invoked) carrying the full guidance, and
- a one-line **SessionStart hook** that reminds Claude the skill exists so it
  fires at the right moment.

## Install — Claude Desktop / claude.ai (copy-paste)

These apps have no plugin marketplace. Open
[`templates/custom-instructions.md`](templates/custom-instructions.md) and paste
the rule block into **Settings → Custom Instructions** (or a Project's
instructions).

## How it works

Skills are model-invoked: Claude consults one when the task matches its
description. The description here is tuned to fire the moment a change would hide
state, and to stay quiet on benign edits (typos, tests, renames, honest
deletions). The session nudge is a lightweight pointer that raises the odds the
skill fires when it matters — the same pattern the Superpowers framework uses.

It is **guidance, not a hard gate**: it prompts Claude to prefer the visible path
or flag the trade-off, not to block anything.

## License

MIT © Heiko Brantsch
````

- [ ] **Step 2: Create `LICENSE` (MIT)**

```text
MIT License

Copyright (c) 2026 Heiko Brantsch

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Validate README has both install paths and LICENSE names the author**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
grep -q "/plugin marketplace add haiggoh/no-hidden-changes" README.md \
  && grep -q "templates/custom-instructions.md" README.md \
  && grep -q "Heiko Brantsch" LICENSE \
  && echo "readme+license OK"
```
Expected: prints `readme+license OK`, exits 0.

- [ ] **Step 4: Commit**

```bash
cd ~/ClaudeWorkspace/no-hidden-changes
git add README.md LICENSE
git -c user.name="Heiko Brantsch" -c user.email="noreply@haiggoh.dev" commit -m "docs: add README and MIT license"
```

---

### Task 6: Full-repo validation pass

**Files:**
- No new files (verification only).

**Interfaces:**
- Consumes: all files from Tasks 1–5.

- [ ] **Step 1: Confirm the full expected file tree exists**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json \
         skills/no-hidden-changes/SKILL.md hooks/hooks.json \
         templates/custom-instructions.md README.md LICENSE; do
  test -f "$f" && echo "OK  $f" || { echo "MISSING $f"; exit 1; }
done
```
Expected: seven `OK` lines, exit 0.

- [ ] **Step 2: Validate every JSON file parses**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  jq empty "$j" && echo "valid $j"
done
```
Expected: three `valid ...` lines, exit 0.

- [ ] **Step 3: Confirm working tree is clean (all work committed)**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
git status --short
```
Expected: no output (clean tree).

- [ ] **Step 4: Print the tree for a final human eyeball**

Run:
```bash
cd ~/ClaudeWorkspace/no-hidden-changes
git ls-files
```
Expected: lists the spec, plan, and all seven deliverable files.

---

## Post-plan (out of scope, after session restart)

1. Restart Claude Code so the GitHub MCP loads.
2. Create the empty public repo `haiggoh/no-hidden-changes` (grant the token `Contents:write`).
3. Push via the GitHub MCP `push_files` (the token can't be materialized for plain `git push`), then verify anonymously with `git fetch origin` + `git diff`.
4. Smoke-test install in a fresh session: `/plugin marketplace add haiggoh/no-hidden-changes` → `/plugin install no-hidden-changes@haiggoh`; confirm no "Duplicate hooks" error and the skill shows in `/skills`.

## Self-Review notes

- **Spec coverage:** manifests (§3, §4.4) → Task 1; SKILL.md description+body (§4.1) → Task 2; nudge hook + duplicate-hooks guard (§4.2, §6) → Task 3; Desktop template (§4.3) → Task 4; README origin + LICENSE (§8) → Task 5; testing/verification (§7) → Tasks 1–6 validation steps + Post-plan smoke test. Build phases (§9) → task order + Post-plan section.
- **Placeholder scan:** none — every file's full content is inline.
- **Type/name consistency:** `no-hidden-changes` (plugin/skill), `haiggoh` (marketplace), source `./`, and the skill name referenced by the hook/README all match across tasks.
