---
title: A batched capture carries its plan's order into depends_on
when: both
tags: [capture, dependencies, plan]
check: For each ordering sentence in the plan the captures come from ("X then Y", "after Z", "in parallel"), which `depends_on` line enforces it, including edges to issues captured earlier (scaffolding, a gate) and from them (a later retirement), and does the land add the edges that already-captured drafts need to the new ids?
---
`ready` orders rafts only through `depends_on`, so an order written in a plan and not in the frontmatter is lost the moment its issues are captured. A batch of captures from one plan must carry every ordering sentence, also toward issues captured before (they need the new ids, which exist only from this land on, and `land` can still edit a draft's `depends_on`), and must not add order the plan doesn't have ("run in parallel").

**Why:** c0190 design review 001 F1 and F5: the step-2 list's issues depended only on each other; none waited for c0184 (scaffold the homes) or c0185 (the cross-home gate), the views didn't wait for the input cores, and c0188 (retire the lobby) didn't wait for the portal, although c0183's plan ordered all of it.

**How to apply:** list the plan's order sentences next to the dependency table, one row per edge, and give the land a step that adds the new ids to earlier drafts' `depends_on`.

c0190 design review 004 F5: for a handover across several issues (a lobby replaced by a portal), name every intermediate state and what each issue does in it, so no step leaves a path (a game over) leading nowhere.
