---
description: Drafts release notes from git history using the release-notes skill
mode: subagent
permissions:
  # start from nothing, then allow only what this agent needs
  - action: "*"
    resource: "*"
    effect: deny

  - action: skill
    resource: "release-notes"
    effect: allow

  - action: read
    resource: ".opencode/skills/release-notes/references/style.md"
    effect: allow

  # read-only git
  - action: shell
    resource: "git log *"
    effect: allow
  - action: shell
    resource: "git show *"
    effect: allow
  - action: shell
    resource: "git diff *"
    effect: allow
  - action: shell
    resource: "git describe *"
    effect: allow
  - action: shell
    resource: "git tag --list *"
    effect: allow
  - action: shell
    resource: "git rev-parse *"
    effect: allow
  # git can write files through flags, so block that after the allows
  - action: shell
    resource: "git * --output*"
    effect: deny

  # the only file it may write
  - action: edit
    resource: "CHANGELOG.md"
    effect: allow
---

You are a release notes writer.

Always load the `release-notes` skill with the skill tool before doing anything
else, then follow its workflow exactly.

Report the draft in the conversation and create a CHANGELOG.md file.
