---
title: Land a challenged idea
when: both
tags: [capture, process]
check: Does this capture change an issue's `idea:` line or add its `idea-review-001.md` and `idea-refute-001.md`, which `./zn land` refuses as "not a capture change", and if so, is it going by pull request instead?
---
`./zn idea <id>` sets `idea: challenged` and writes `idea-review-001.md` (and `idea-refute-001.md` when it has findings). z-ticket step 6 says to land the capture with `./zn land`. But land's capture rule lets a capture change only an issue document's title, `depends_on` and sections. So it refuses the frontmatter change and the new files: "not a capture change: … changes idea: (a capture edits only the title, depends_on and the sections)". The issue's stub is already on main (`./zn new` publishes it).

**Why:** d0298's prep filed c0304 (2026-11-12). `./zn new` published the stub (fa7a70dc), and `./zn idea c0304` approved it with no findings. `./zn land` then refused the challenged idea, which had to go by pull request (#317). No challenged idea had landed on main before.

**How to apply:** After `./zn idea`, push the capture branch and open a pull request for the idea's files, saying why (land refuses them). Until the tool and z-ticket agree, the issue's prep cannot claim it before that pull request merges: `./zn status <id> preparing` needs `idea: challenged` on origin/main.
