# Agent rules for south-plus-pro

These rules apply only inside this repository checkout. They do not bind other repos, other machines, or the user's global agent config.

Repo-wide skills live under `.agents/skills/`. Before work that a skill covers, read that skill's `SKILL.md`. If a required skill cannot be followed with the static files here (for example a missing plugin, hook, npx install, Node binary, or browser), stop and say what is blocked. Do not skip the skill quietly, and do not claim it was followed.

## Priority order

Apply matching rules in this order. Each line is mandatory for its trigger.

1. Before any read or write in this repo (inspection, docs, tests, and code changes), invoke ponytail in FULL mode from `.agents/skills/ponytail/SKILL.md`. Stay on full unless the user changes the level in chat. Follow the skill text by hand; do not install ponytail plugins or hooks for this repo.
2. Before writing, editing, adding, or running tests, invoke test-audit from `.agents/skills/test-audit/SKILL.md`. For campaign-mode audits, read `CAMPAIGN.md` in that folder first.
3. Before UI, UX, or design work, invoke both `.agents/skills/stop-describing-ui/SKILL.md` and `.agents/skills/taste-skill/SKILL.md` (frontmatter name: `design-taste-frontend`).
4. Before writing or editing comments, UI/UX copy, or docs (including this file), invoke humanizer from `.agents/skills/humanizer/SKILL.md`.

Example: UI copy needs ponytail FULL, then stop-describing-ui and taste-skill, then humanizer. A test change needs ponytail FULL, then test-audit.

## Installed skills

| Directory | Trigger |
| --- | --- |
| `.agents/skills/ponytail/` | Any repo read or write; FULL mode |
| `.agents/skills/test-audit/` | Any test write, edit, add, or run |
| `.agents/skills/stop-describing-ui/` | UI/UX text and interaction design |
| `.agents/skills/taste-skill/` | UI/UX and visual design |
| `.agents/skills/humanizer/` | Comments, UI/UX prose, documentation |

Only these skill bodies are in the tree. Plugin manifests, marketplace hooks, install scripts, and `npx` installs were not added.

## Ponytail FULL coverage

FULL is the main ruleset in `.agents/skills/ponytail/SKILL.md`: smallest complete change, name what you skipped, name any risk. That file does not call for `ponytail-review`, `ponytail-audit`, `ponytail-debt`, `ponytail-gain`, or `ponytail-help`. Upstream ships those as separate optional skills (see `skills/ponytail-help/SKILL.md` and the upstream README Commands table). They are not in this checkout.

In this repo, FULL means agents must read and follow that main skill text before reads and writes. Lifecycle hooks, session injection, mode flag files, the Claude Code band, and the optional review/audit commands are outside this install. Without plugins or hooks, nothing auto-runs. Compliance is manual skill use.

## Taste-skill files on disk

`.agents/skills/taste-skill/` includes static `scripts/`, `assets/`, `library/`, and `references/` for later use. This install did not run those scripts, did not add `node_modules`, and did not install Node or Chrome. A later UI build that uses the checker still needs Node 22+ and a Chromium browser on the host. If that tooling is missing, report the blocker.

## Source pins

| Skill | Upstream | Commit |
| --- | --- | --- |
| stop-describing-ui | https://github.com/artouc/stop-describing-ui | `251a859f6e40645030e1ae69fa4b501c851eac9c` |
| taste-skill | https://github.com/leonxlnx/taste-skill (`skills/taste-skill`) | `9b4bf937a1f69348126959c15d2f99a73e65699b` |
| test-audit | https://github.com/ImoutoHeaven/my-skills/tree/main/test-audit | `6c2b8591ce2711f087bba117b2df1ba7eed17ebd` |
| ponytail | https://github.com/dietrichgebert/ponytail (`skills/ponytail`) | `96608e078b2d5ea607c5c3b8b5a54d1c1fba6846` |
| humanizer | https://github.com/blader/humanizer | `0ef9fe5bc3572734fd3ae6c448fe00a30cd5dcf0` |
