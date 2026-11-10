---
name: release-notes
description: Draft release notes from git history. Use when preparing a tagged release or summarizing changes since the last tag.
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
---

## Workflow

1. Find the previous release tag with `git describe --tags --abbrev=0`.
2. Collect commits since that tag with `git log <tag>..HEAD --pretty=format:"%h %s"`.
3. Group the changes into Added, Changed, Fixed, and Removed.
4. Read `references/style.md` and apply its rules.
5. Present the draft to the user before writing it to a file.

## Rules

- Mention the commit short hash in parentheses for every bullet.
- Skip merge commits and version bump commits.
- Do not invent changes: only describe what the commits contain.
- Ask for the target version if it cannot be inferred from the tags.
