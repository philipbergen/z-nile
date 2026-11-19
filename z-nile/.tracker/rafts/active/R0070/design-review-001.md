# Review 001: R0070 (design mode, raft mode)
Inputs: branch raft-znile-backlog at 451073e5 (origin/main c0e15bb0); R0070.md, R0070/check.sh; c0189.md, c0189/check.sh, c0189/acceptance/{wiring,repo-hook,hooks-plan,hooks-command}.spec.luau, c0189/experiments/prototype.patch; c0194.md, c0194/check.sh, c0194/acceptance/{docs,callers,tmp,shim,runner}.spec.luau, c0194/experiments/prototype.patch; z-ready, zz-rules, z-design, zz-execute, zz-test skills; R0039.md, c0075.md, c0157.md, c0191.md, c0178.md front matter; `./zn workstreams R0070`; `./zn lessons --skill z-raft --full`.
Grouped: [c0189@517cbf1b5d80, c0194@ab969aed993b]

Method. I made a scratch clone of 451073e5 outside the repository (the session scratchpad, origin removed, nothing committed). There I applied c0189's prototype patch, then c0194's with `--3way`. Conflicts came up only in z-design, zz-execute, zz-rules and zz-test. I settled each one by keeping both members' text, in the order the raft's Whole-raft design gives (Merging step 2: c0194's clone sequence, then c0189's "Run `./zn hooks` in the clone (…a fresh clone has no hook of its own).", then c0194's verify sentence). Then I ran the members' specs on that combined tree:
- `c0189/wiring` + `c0194/docs`: **20 passed, 0 failed**. Every literal pin of the two specs can hold in one text, the 4000-character window of c0194's main-checkout case included.
- `c0189/{repo-hook,hooks-plan,hooks-command}`, `repo-fence`, `c0055/setup-run`, `c0172/merge`: 82 passed, 3 failed. The three failures are all `c0172/merge`, c0194's declared Override, which its prototype does not apply.
- `c0194/{tmp,shim,runner}`: 47 passed, 0 failed.
- `c0194/callers`: **8 passed, 1 failed** (F2).

The pins are compatible as text. The findings below are about what they say, and about one pin that is not.

### F1 [high] The combined prototype rule still sends scratch clones to "`$TMPDIR` or the scratchpad", against c0194's captured outcome; the raft passes both pins but drops that outcome
Where: R0070.md Whole-raft design, "The prototype rule" bullet (its "Resolution"); c0189.md "The rules in prose" and the hook's message; c0194.md Problem, Non-goals, AC5, Existing work (c0189, c0157), Implementation step 8.

Evidence:
- c0189's `wiring.spec` pins, word for word, in z-design, zz-execute and zz-test: "A prototype or experiment lives in a scratch clone (a `git clone` of the checkout into `$TMPDIR` or the scratchpad) …".
- c0194's captured Problem: "Nothing builds a tree outside the repository any more. The skills name `.cache/.tmp/` as the place for an experiment's or prototype's scratch clone; **c0189's "scratch clone" wording points there too.**"
- c0194's Non-goals: "The skills still send repo clones to `.cache/.tmp/`, not there [the scratchpad]."
- c0194's AC5: "nothing still sends a clone to `$TMPDIR`".

On the combined tree, z-design's experiments bullet reads "… An experiment that needs a clone … makes it with `./zn tmp new <kind>` (under `.cache/.tmp/`, never the system temp folder) … A scratch clone (never a `git worktree add`) goes under `.cache/.tmp/` …". The next bullet says a prototype "lives in a scratch clone (a `git clone` of the checkout into `$TMPDIR` or the scratchpad)". zz-execute Phase 1 has the same two sentences one after the other. The scratchpad (`/private/tmp/claude-501/…`) is outside the repository. `$TMPDIR` is `.cache/.tmp` only in a Claude Code session started after c0194's SessionStart hook exists. c0194 itself lists what that misses: the Claude Code `sandbox` setting, sessions started before the hook, and any non-Claude agent, which z-ready's prompt is written for ("any agent (Opus, Grok, ...)"). So the raft's "`$TMPDIR` is `.cache/.tmp` in every session once c0194 lands, so 'into `$TMPDIR`' is the same place" does not hold. Its parenthesis cites c0194's Non-goals as if they allowed the scratchpad, but they say the opposite.

The docs.spec pin `lacks("clone under \`$TMPDIR\`")` passes only because c0189 writes "clone of the checkout into `$TMPDIR`". No check fails, which is why this has to be caught here.

The hook's refusal text (c0189, not pinned beyond "scratch clone") repeats "git clone this checkout into $TMPDIR or the scratchpad".

c0194's way of reconciling the two (Existing work, and step 8: "adds a dated note under each draft's captured text … they stay drafts; their own preps take it from there") was written while c0189 was a draft. c0189's prep is now finished and did not take the definition up. A note under c0189.md in this raft changes nothing, and no later prep of c0189 will read it.

Critique: the tempting fix is to leave both sentences, as the Resolution does, because both specs are green. The members' gates can't tell that the text contradicts itself. An agent reading z-design gets two places for the same clone, and one of them is the folder the user asked to stop using. The other way out, having c0194's executor reword c0189's sentence, edits a sequestered spec (`wiring.spec`'s `RULE`) without a declared exception.

Consequences: c0189's design and specs change: the `RULE` constant in `wiring.spec`, the three skill sentences, the hook's message line, and the lesson's wording. That means a c0189 re-review round, and its `grouped:` hash changes. c0189's sentence then names `./zn tmp new`, a command only c0194 delivers. Both land in one PR and `wiring.spec` is a text pin, so wave order and both stream gates are unaffected, but the sentence is only true once both are merged. c0194's step 8 loses its c0189 note (a small change to c0194's document). The note under c0157.md stays (F8). One wording question needs an answer: may the harness scratchpad still hold non-repository scratch files? c0194 forbids only repository clones there.

Recommendation: the raft lead changes c0189 in this rafting branch and folds it again at the end (z-raft lesson rafted-member-changes-stay-in-the-raft), or unfolds it, so c0189's design changes as follows:
- `RULE` becomes one sentence that includes c0194's pinned fragments or names its place, for example "A prototype or experiment lives in a scratch clone (never a `git worktree add`) under `.cache/.tmp/` (`./zn tmp new <kind>`), or commits under your own identity, and never commits as `@example.invalid` in the real repository or any worktree of it: …".
- The hook message's last line says the same.
- The lesson keeps "in a scratch clone or worktree (z-design, Unknowns & experiments)". It points at the rule, so it follows the rule.
- c0194's step 8 drops the c0189 note.

Add a case to `wiring.spec` (or one raft RC) that `lacks` "or the scratchpad" and "into `$TMPDIR`" in the five files c0194 names. Its mutant is the old sentence restored. Then rerun both specs on the combined prototype, as above.

Candidate lesson (z-raft, new): two members' pinned sentences that both pass can still contradict each other. After running the specs on the combined text, read the combined paragraph against each member's captured Problem. Check: does the merged paragraph deliver every member's captured outcome, or does it only pass both pins?

### F2 [high] c0194's sequestered scan (`callers.spec`) fails on c0189's `mktemp` in `main.luau`; neither member nor the raft lists it
Where: c0194/acceptance/callers.spec.luau `ALLOWED` and "no tooling line makes a temporary tree outside z-nile/lib/tmp.luau but the reviewed ones" (AC4); c0189.md `./zn hooks` install ("`mktemp <dir>/.reference-transaction.new.XXXXXX`", Rules row F4m); R0070.md Whole-raft design, `main.luau` bullet ("Different commands").

Evidence: on the combined tree, `lune run tests/run -- c0194/acceptance/callers.spec.luau` gives 8 passed, 1 failed: `expected "", got "z-nile/engine/main.luau: tmp = sh.must(\"mktemp\", { \`{dir}/.{hooksLib.NAME}.new.XXXXXX\` })"`. The scan flags every non-comment line under `z-nile/` that contains `mktemp`, unless its file has an `ALLOWED` fragment, and `main.luau` has none. The raft orders c0189 in wave 1 and c0194 in wave 2. So c0194's stream gate, and RC0's loop over c0194/check.sh, go red at once. The executor may edit neither spec, so this is a zz-execute stop condition. It is the only cross-member red I found (all the specs above ran).

Critique: there are two tempting fixes, and both are wrong. One is to reword the Luau so the token `mktemp` is not on the line (a variable, a split string): that games a guard. The other is to drop c0189's unique name for a fixed `.reference-transaction.new`: c0189's design review 003 F4 removed exactly that, because two concurrent installs could move each other's non-executable file into place.

Consequences: either option changes a member's design.
- (a) c0194's `callers.spec` gains `["z-nile/engine/main.luau"] = { [".new.XXXXXX"] = "a file beside the installed hook in the git directory, renamed into place; not a tree (c0189)" }`. This mirrors the existing `fence.sh` `.sentinel.XXXXXX` entry. It is a one-line change to a sequestered spec, so c0194 needs a short re-review, and its `grouped:` hash changes. The new mutant is the entry removed, and the scan then fails on c0189's line.
- (b) c0189's install makes its unique sibling name without `mktemp` (for example an exclusive create through `replace-file.pl` under a pid-and-random name, then `chmod`, `mv`). c0189's Design and row F4m change, and the concurrency property needs a stated mechanism.

Recommendation: (a). The allow-list exists for reviewed non-tree temp files, and a hook beside the git directory's hooks is one. It keeps c0189's reviewed install unchanged. Either way, the Whole-raft design names this interface, and the lead reruns `c0194/callers` (and every member spec) on the combined prototype before `ready`.

Candidate lesson (z-raft, new): run every member's sequestered specs, repository-wide scans and allow-lists above all, on a tree with all members' prototype patches applied. "Independent in code" is a claim about modules, but a scan reads every file. Check: has each member's whole acceptance set run on the members' prototypes applied together, and is every red case either a declared Override or a named interface?

### F3 [medium] The user's decision "c0194 first" (R0070 before R0039) is enforced by nothing; the raft's claim that z-ready checks it is false
Where: R0070.md Order & dependencies, "Cross-raft" ("z-ready checks, for the lead, that this raft is `done`"); c0075.md (`depends_on: []`); R0039.md (no mention of R0070 or c0194); z-ready SKILL step 2.

Evidence: z-ready's only cross-item check is "Every `depends_on` of a member issue that isn't a member of this raft names an item in `done/`". c0075 has `depends_on: []`, and R0039 (single, `design: ready`, prepared) names neither R0070 nor c0194. So anyone can run `./zn ready R0039` today, and z-ready won't stop it.

If R0039 is readied while R0070 is running, c0075's specs move to `active/`. c0194's executor then edits the sequestered specs of an active raft (its Overrides name the backlog path `z-nile/.tracker/issues/c0075/acceptance/…`). That collides with R0039's own executor, and R0039's code review item 2 flags it as high. If R0039 lands first, c0194 has a fallback (edit the promoted copies), but the user's order is broken.

R0073 ("land R0070 first there too") has the same gap.

Critique: a sentence in R0070.md is read by no one who readies R0039.

Consequences: c0075 gains `depends_on: [c0194]`. z-ready then stops R0039 until c0194 is in `done/`, and `./zn audit` must accept a `depends_on` on another raft's member. If the rules give c0075's front matter only to c0075's own prep, the lead asks the user, or records the order in R0039.md and on c0075, where its readier reads it. For R0073, say whether the order is required (then the same mechanism) or only simpler (then say so, and leave it unenforced).

Recommendation: record the order where z-ready enforces it (c0075 `depends_on: [c0194]`, made in this rafting PR if the rules allow it, otherwise by the route above). Correct the Order's sentence, and add a matching line for R0073 or drop "first" there.
Lesson: z-raft/order-reasons-survive-workstreams ("An order execution must follow goes in `depends_on`").

### F4 [medium] RC2 proves nothing about coexistence, and costs over two minutes of machine-dependent work
Where: R0070/check.sh RC2; R0070.md Exit criteria.

Evidence:
- `./zn hooks --check` is run while the raft is unmerged. `origin/main` then has no `z-nile/lib/repo-hooks/reference-transaction`, so c0189's table returns `none`: it prints "nothing to install or check" and exits 0, whatever is installed. This holds in every run of `./zn check R0070` and `./zn done R0070`.
- "Read-only" is asserted but never measured: nothing is compared before and after.
- `./zn tmp leftovers` took **141 s** on this machine (`du -sk` over 14 GB of old trees in the user temp folder; 2.9 s user, 80.6 s sys). Its time grows with the machine's leftovers, and its outcome depends on files outside the repository.
- `bash -n` passes, and `$ZN_ROOT` is exported by ac.sh, so RC2 runs. It just tests almost nothing.

Meanwhile the actual seam between the members has no check: Merging step 2, where c0194 makes and verifies the clone and c0189 installs and checks the hook in it.

Critique: the tempting fix is to keep RC2 and add `--dry-run` flags. It would still be vacuous before landing.

Consequences: a replacement RC writes a fixture under `.cache/`, and reads the real repository only to clone it. It must run unjailed safely, because `check.sh` commands are not jailed, so review checks every write path. `./zn hooks` in the clone writes that clone's `.git/hooks` only.

Recommendation: replace RC2 with the Merging sequence in a fixture:
1. `dir=$("$ZN_ROOT/zn" tmp new rc2 --dir "$PWD/.cache/r0070-rc2")`;
2. `git clone --no-hardlinks --no-checkout "$ZN_ROOT" "$dir"`, `git -C "$dir" remote remove origin`, `git -C "$dir" checkout --detach HEAD`;
3. `./zn hooks` then `./zn hooks --check` in `$dir`: exit 0 and "installed in";
4. `"$ZN_ROOT/zn" tmp verify "$dir"` prints `isolated`;
5. `"$ZN_ROOT/zn" tmp rm "$dir"`, and `$dir` is gone.

Every write is under `.cache`. Drop `leftovers` from the gate: it is c0194's Phase 1 report to the user, not an exit criterion.

Candidate lesson (z-raft, new): an RC that runs a command whose "nothing to judge yet" state is a pass (here `none` until `origin/main` has the file) is vacuous for the whole raft. Check: what does each RC print on the raft's own branch before it merges?

### F5 [medium] The Theme says c0189 relies on no user decisions, but c0189 carries four decided and two pending ones
Where: R0070.md Theme ("c0189 none beyond its capture"); c0189.md Problem (Decided with the user 2026-10-31, 2026-11-01) and Guesses G1, G3.

Evidence:
- c0189 records "New fast chore" and "Yes, retry once" (2026-10-31), and G2 "Accept" and G4 "Delete them" (2026-11-01).
- The retry-once decision is the text c0189's `RETRY` pins in AGENTS.md and zz-test. R0070's own Risks rely on it ("retried once").
- **G1 (pending user)** widens `repo-fence.spec`: `hooks.luau` may name the hooks-folder setting, and `repo-hook.spec` may commit under four non-fixture addresses. That is a guard relaxation, and zz-review code mode item 8 treats any weakening of `repo-fence.spec` as high.
- **G3 (pending user)** reads "any ref update" as leaving pseudo-refs alone.

Critique: the executor will reach the `repo-fence` edits with G1 unanswered, and so will the code reviewer, who has nothing in the raft telling them it is pending.

Consequences: if the raft executes on the recommended guesses, then by the user's standing rule (branch on a guess, never merge it) it cannot merge until G1 and G3 are answered. That belongs in Risks.

Recommendation: the Theme quotes c0189's four decisions and names G1 and G3 as pending. Either ask the user before `ready`, or state in Risks that the raft can't merge until they are answered, and that the code reviewer is told G1 is the declared, pending widening.

### F6 [low] After both land, a gate run inside `./zn tmp jail` fails at c0189's hooks stage, and neither text says how to avoid it
Where: c0194 zz-test "Running specs against unguarded code" (the jailed clone); c0189 gate stage `./zn hooks --check`; R0070.md Whole-raft design.

Evidence:
- The jailed clone is `git clone`d with origin removed, so `./zn hooks --check` judges the tree's copy and finds no installed hook. It reports "missing; run ./zn hooks" and exits 1.
- `./zn hooks` inside the jail cannot write the clone's `.git/hooks`: c0194 E12d shows the profile denies the clone's git directory.
- Merging step 2 runs `./zn hooks` in its clone for exactly this reason, but the unguarded-code recipe doesn't.

The recipe today runs spec files (`lune run tests/run -- <spec>`), not the gate, so this only bites an agent who runs `z-nile/check.sh` there.

Critique / Consequences: a sentence in zz-test (c0194's unpinned text) settles it. It needs no spec change.

Recommendation: the Whole-raft design tells c0194's executor to add one sentence to the unguarded-code bullet. It can say the jailed clone runs spec files, not the gate. Or it can say: to run the gate there, first run `./zn hooks` in the clone outside the jail, using main's code (not the prototype's).

### F7 [low] Several Whole-raft design statements don't match the members
Where: R0070.md Whole-raft design and Exit criteria.

Evidence:
- (a) "c0189 adds the `hooks [--check]` command (usage line, `READ_ONLY`/main-checkout lists …)": c0189 says it is **not** in `READ_ONLY` (`guardRepoRoot` runs first).
- (b) `setup.sh`: "c0194 writes `env.TMPDIR` / installs the SessionStart hook and the `.cache/.tmp` marker": c0194's `setup.sh` change is only the rokit download under `.cache/.tmp/rokit.XXXXXX`. Its hook is checked in through `.claude/settings.json`, and its design rejects a `settings.local.json` `env` block.
- (c) `check.sh`: "c0194 … adds its own stage lines": it adds `source z-nile/lib/tmp.sh`, a sweep and two maker calls, and no `par_start` stage.
- (d) "the z-design lesson `prove-specs-pass-on-a-prototype` reads 'in a scratch clone or worktree'" "as c0189 pins it": no spec reads that lesson.
- (e) RC1 runs the same two specs that RC0's member loop already runs on the same final text, so it adds no evidence. Keeping it is harmless, but it does not prove what F1 shows is missing.

Critique / Consequences: an executor who trusts (a) or (b) edits the wrong place. None of these changes a member.

Recommendation: correct (a) to (d) in the Whole-raft design. Either give RC1 real work (F1's `lacks` case), or say it repeats RC0 on purpose.

### F8 [low] c0157 is being prepared now on the same lines, and the Order doesn't mention it
Where: R0070.md Order & dependencies and Risks ("adds dated notes under c0189.md and c0157.md"); c0157.md (`status: preparing-raging-indigo-mongoose`, `design: draft`; its Solution names "a z-design / zz-execute rule that prototypes li[ve in scratch clones]").

Evidence:
- c0194's step 8 edits c0157.md while another session's prep holds c0157.
- c0189 says c0157's Part 2 (the same sentence in the same three skills) moved to c0189, and "whichever lands second merges them".
- If c0157's prep pins its own prototype-rule wording, that would be a third pinned sentence for these paragraphs. Nothing in R0070 tells c0157's prep what R0070 pins.

Critique / Consequences: the R0070 PR and c0157's prep PR both edit c0157.md, so they conflict. c0157's prep may re-pin a contradicting sentence.

Recommendation: name c0157 in Order & dependencies as in flight on the same skill lines. The lead tells c0157's prep session what R0070 pins (after F1's fix), so its prep quotes it (lesson z-design/quote-other-preps-before-promising). Keep the dated note, but make it the corrected definition.

Verdict: unfold c0189 (F1, and F2 unless c0194 takes the one-line `callers.spec` entry, which unfolds c0194 too); approve after fixes for F3 to F8 in the raft document and check.sh.
