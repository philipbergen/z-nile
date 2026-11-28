# Idea review 003

## Findings

- F1: The skip rule in Solution bullet 4 cannot match the rows the typed command writes, so a stage that already has a typed row gets a second one. `./zn spend` appends the reading note to the subject (`main.luau:7727`): the tracker holds 28 rows shaped `design-review-NNN claude unmeasured; grok unmeasured; agent unmeasured; kimi unmeasured`, 17 such refute rows and one `design-review-NNN (declared)`. A typed raft row also has no `R0158 ` prefix. None of these equals `design-review-001` or `R0158 design-review-001` exactly, the Non-goals keep the typed command, and the capture asked for "idempotent when a manual row was already recorded".
- F2: Solution bullet 5 and Non-goal 2 remove grok from the measured CLIs, which the captured Solution names (`claude`, `grok`, `kimi`, agy; `./zn capture c0466`), and no `Decided with the user` line records that cut. No new reader is needed to keep grok: the typed call these rows replace measures with `sessionread.span` (`main.luau:7717`), which reads grok (`sessionread.luau:153-172`). Only `sessionread.running` sets grok to nothing (`sessionread.luau:229`).
- F3: Bullet 5 says the row "is measured" but not what quantity, so a reader cannot check its value. The typed rows it replaces hold one stage's span (the reviewer's run, the answering span of z-raft:44), while `sessionread.running` reads the whole session ("Not a time span", `sessionread.luau:205`). The idea does not say whether `prep`, `design-review-001` and `design-refute-001` rows written in one session each hold their own stage or the session's running total, which would count the early stages several times when summed.
- F4: Bullet 3's "never shares a subject with a member's own round" is false under Non-goal 3. A raft review started with `./zn dispatch zz-review <R-id> --mode raft` gets its row from the dispatcher under the bare file name `design-review-NNN` on each member (`dispatcher.luau:1259`, zz-rules `SKILL.md:193`), and Non-goal 3 leaves that row unchanged. That row also differs from `R0158 design-review-001`, so bullet 4's test would not see it for the same round.

## Verdict

revise
