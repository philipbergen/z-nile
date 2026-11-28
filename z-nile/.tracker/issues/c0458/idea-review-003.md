# Idea review 003

## Findings

- F1: The third non-goal ("does not drop any of zz-review Code mode's checks") contradicts the Solution's own list. Code mode (`z-nile/skills/zz-review/SKILL.md:114`) also has Sequestration, Weak tests, Design adherence, Architecture rules, Performance, Lessons and the ruling-line check (11a). The Solution's list names only correctness, regressions and Overrides, repository safety, bounded commands and Judged criteria, so a normal or risky raft would lose the unnamed checks it gets per layer today. The list is also cited to `work.luau:792`, which only says "the final review covers the code"; the list itself is at `work.luau:347`.
- F2: The Problem's "the engine only refuses…" is false, so removing `readycheck.luau:235` alone does not deliver the last Solution bullet. `work.luau:736` (worded at `:806`) makes `./zn work next` answer `draft` for a prepared easy ticket that is not light and has no design review. The worker is sent back to the full design path and never reaches the `ready` that the Solution unblocks.
- F3: No sentence says whether the final review judges the design of a `normal` ticket that skipped its now-optional design review. The Solution says so only for an easy ticket's short note and design, so a reader cannot tell whether a normal ticket's design gets any adversarial look, and the riskier ticket may get less than the easy one.
- F4: The `code-review` removal list leaves two dependants unstated. `dispatch.REVIEW_MODES` still accepts `--mode stream` (`dispatch.luau:53`), which `models.roleFor` and `models.activityFor` resolve to `code-review` by default (`models.luau:992`, `:1283`). `WRITER_OF` keeps `code-answer` (`models.luau:115`), the answer to a review that no longer exists. A reader cannot tell whether a stream review can still be filed, which bears on "exactly one adversarial `final-review`".

## Verdict

revise
