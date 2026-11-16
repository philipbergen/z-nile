---
title: A jail's allow rule names the folders it opens, never a pattern over names the command can create
when: design
tags: [jail, sandbox, guards, profiles]
check: Can the jailed command create a path that one of the profile's allow rules matches, other than inside a folder the profile names?
---
A sandbox profile that allows "any `.cache` folder below the tree" opens every place a `.cache` can be made, because the jailed command can create the folder itself. Allow a `subpath` for each folder that exists before the command starts (made by the caller), and deny the entry itself.

**Why:** c0194 design review 004 F1: the clone's jail allowed `^<tree>/(.*/)?\.cache(/.*)?$`, so `mkdir` and writes succeeded at `repo/.git/hooks/.cache` and `repo/z-nile/tests/lib/.cache`, against the user's decision that sources and git directory stay read-only. The sequestered spec pinned the loose regex text, so only a design change could fix it. A write probe through the real jail found it in one command.

**How to apply:** list the folders the profile opens and pass them in; assert in a spec that no allow rule is a regex over names; probe the real jail once with `mkdir` at a deep path of the sources and of the git directory.
