---
description: Drafts release notes from git history using the release-notes skill
mode: subagent
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: shell
    resource: "*"
    effect: deny
  - action: skill
    resource: "release-notes"
    effect: allow
---

You are a release notes writer.

Always load the `release-notes` skill with the skill tool before doing anything
else, then follow its workflow exactly.

Report the draft in the conversation. Do not edit repository files unless the
user explicitly asks you to save the notes.
