# Review 005: c0122 (design mode)
Inputs: worktree `prep-fence-accepts-empty-fetch` at 0d4323b4, plus its uncommitted `c0122.md`, `check.sh`, `acceptance/{fetch,refuse,wording}.spec.luau`, `design-review-00{1..4}.md`, `design-refute-00{1..4}.md` and `harvest.md`; `z-nile/lib/fence.sh`, `z-nile/lib/git-hooks/reference-transaction`, the zz-test Ref guard bullet; c0123's prep (`prep-fence-verifies-inherited-hooks`: `experiments/prototype.patch`, `acceptance/wording.spec.luau`); `./zn capture c0122`; `./zn lessons --when design --full`, `./zn lessons --skill zz-review`.
Dropped from design-review-004: F1, F2. Their fixes hold: with `--atomic` the refusals are whole on both gits, and `tagOpt=--tags` in `PINS` makes the tag case independent of the host's `tagOpt`.
Runs (every command time-bounded; one `mktemp -d` folder holding a `--no-hardlinks` clone of the worktree with the prep files copied in and fixtures beside it, deleted afterwards; fixture commits as `x@example.invalid`):
- `./zn promote-check c0122`: OK. `./zn lessons --uncovered c0122`: every finding covered.
- Items 1 to 3 applied to the clone, taken mechanically from the document's text (item 1's line, item 2's line, item 3's block inserted before c0172's): `wording` + `fetch` + `refuse` on git 2.54.0, 15 passed, 0 failed. `fetch` + `refuse` on git 2.50.1 (`PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH`), 11 passed, 0 failed.
- On 2.50.1, M14 (`refs/tags/*` allowed) fails only the tag case, and M2 (empty accepted in spec runs) fails only the spec-run case.
- c0123's appended sentences on top of item 1's line: c0123's Ref guard wording case and c0122's four AC3 cases pass. c0123's other two cases need its other edits, which weren't applied.
- I ran hand fixtures through this worktree's `pickman_fence` in check mode on both gits (results in F1 and F2).

No high or medium finding remains. The captured Outcome is fully designed and pinned on both gits on hand, and no spec or check can write outside `.cache`.

### F1 [low] The new sentence's parenthetical about git 2.50.1 is false for two of the classes it governs
Where: Design item 1 ("the whole fetch is refused only with `--atomic` (git 2.50.1 refuses a plain fetch ref by ref, after it has moved the `refs/remotes/` ones)"), AC3's fifth phrase, the Prep finding.
Evidence: plain (non-atomic) fetches, check mode, git 2.50.1, `PINS`-style `-c` prune keys false:
- `git fetch --prune` after the origin deleted `gone` and committed: exit 128 with the guard's message, `origin/main` unmoved, `origin/gone` kept. The whole fetch was refused.
- A clone whose `remote.origin.fetch` lists `+refs/heads/*:refs/heads/up/*` before `+refs/heads/*:refs/remotes/origin/*`, after a new commit: exit 128, `origin/main` unmoved, no `up/main`. Git stopped at the first refused ref, before reaching the `refs/remotes/` one.
- Only the plain default tag-follow moved `origin/main` before it was refused. The case 5 layout (the up refspec added after the default) gives the same result, as review 004 saw.
Critique: the parenthetical states as a general rule something measured for one ref order and one class. It is harmless in practice, because the safe form is atomic, but it is a false sentence in the rule text, which is exactly what this issue exists to correct. The tempting fix is to name the classes for which it holds. That turns the parenthetical into a list of exceptions again, the mechanism of review 001 F3, 002 F2 and 003 F1.
Consequences: the AC3 phrase changes. c0123 is unaffected, because its wording spec pins only its own appended sentences (run above).
Recommendation: weaken it to what is measured, with no list. For example: "(without it, git 2.50.1 gives each ref its own transaction, so a refused fetch may already have moved some `refs/remotes/` refs)". Pin that phrase in AC3 in place of the fifth one, and say the same in the Prep finding.

### F2 [low] No case pins default tag following any more, though the Design, the case title, the Rules row and the sentence all describe it
Where: The end-to-end specs, `refuse.spec` case 3 ("a default `git fetch origin` is refused ... (git follows the tag into `refs/tags/`)"); the case title "follows a new tag"; the Rules row "a fetch that would follow a tag into refs/tags/ is refused whole"; `PINS` (`remote.origin.tagOpt=--tags`).
Evidence: since round 4's fix, every fetch in case 3 carries `-c remote.origin.tagOpt=--tags`. The tag therefore comes from an explicit `refs/tags/*:refs/tags/*` refspec in the main ref map, not from auto-following (backfill). Backfill is the path whose atomicity differs between git versions (review 004 F1 recalled tag backfill under `--atomic` as a later git than `--atomic` itself), and it is what a check meets with a default fetch. Hand fixtures show that it holds today on both gits on hand. `git fetch --atomic -q origin` with no `tagOpt` and a new tagged commit exits 128, with `origin/main` unmoved and no tag, on 2.54.0 and on 2.50.1. A host-independent form exists too. `git fetch --atomic <origin path> '+refs/heads/*:refs/remotes/origin/*'` follows the tag when unfenced (`refs/tags/v1` is created) on both gits. No `remote.origin.*` key applies to a URL fetch, so it is unaffected even with a global `remote.origin.tagOpt=--no-tags`. Fenced in check mode it is refused whole on both (exit 128, the guard's message, `origin/main` unmoved, no tag).
Critique: the Design says one thing and the spec pins another (lesson z-design/spec-design-correspondence). The path the sentence most needs pinned, a default fetch's tag following under `--atomic`, is now in no case. A git whose backfill sits outside the atomic transaction would make "refused whole" false for a default fetch, and nothing would show it.
Consequences: case 3 gains one fetch (or the case is split), and the Rules row gains a mutant line. The URL form leaves `remote.origin.*` out by construction, so it needs no new `-c` key, and `PINS`' `fetch.*` keys still apply.
Recommendation: keep the `tagOpt=--tags` fetch, retitled "a fetch that writes a tag", and add the URL-form default-follow fetch: `fetch --atomic -q <origin> +refs/heads/*:refs/remotes/origin/*` with `PINS`' `fetch.*` keys, expecting refused, the guard's message, `origin/main` unmoved and no tag. Run it on both gits and against M14. Correct case 3's Design line and its Rules row to name both fetches.
Lesson: z-design/spec-design-correspondence

### F3 [low] On git 2.50.1, AC1 never sends a multi-ref transaction, so a hook that accepts only one-ref fetches passes AC1
Where: `fetch.spec` AC1 (the `brings`, `nothing` and `after` fetches are plain; the safe-form fetch moves one ref); the Rules row "a fetch that creates or moves a remote-tracking ref succeeds".
Evidence: the mutant replaced line 49's `[ "$lines" -gt 0 ]` with `[ "$lines" -eq 1 ]`. On 2.54.0 it fails both AC1 cases (`after=refused…`; the safe form `staleKept=false`) and the prune case: 8 passed, 3 failed. On 2.50.1 both AC1 cases pass, because the plain `after` fetch is two one-ref transactions there. It dies only in `refuse.spec`'s prune case, and only because that case's setup fetch (`first`, atomic, `gone` created and `main` moved) is refused (`first=false … ok=true`): 10 passed, 1 failed.
Critique: the rule's own case doesn't kill the mutant on the older git. Something else kills it, through a setup line that a later edit could drop (lesson z-design/spec-design-correspondence: "killed by that case itself, not first by an older, stricter case"). The mutant is a one-character slip in the hook's accept line.
Consequences: none beyond the one fetch. M12 (creations refused) is still killed by an atomic `after` on both gits, and the plain `brings` and `nothing` fetches stay plain, as review 004 asked.
Recommendation: make AC1's `after` fetch atomic, so the move and the create are one transaction on every git. Add the mutant to the Rules row and run it on both gits.
Lesson: z-design/spec-design-correspondence

### F4 [low] AC3 does not pin the new sentence's subject: "Any git may fetch: it may create …" passes
Where: `wording.spec` bullet case, first phrase (`may fetch: it may create or move refs under …`); Design item 1 ("reads, exactly").
Evidence: in the clone with item 1 applied, I replaced `Only a `check.sh` flow started outside any spec run may fetch: it may create` with `Any git may fetch: it may create`. `wording.spec`: 4 passed, 0 failed.
Critique: the subject is the rule's main qualifier (who may fetch). The later "during a spec run every update is refused" softens the error, so this stays low. But the Design says the sentence reads "exactly", and the pin leaves its first words free.
Consequences: none. c0123 appends after the sentence and pins only its own additions.
Recommendation: start the first phrase at `Only a `check.sh` flow started outside any spec run may fetch: it may create …`, or pin item 1's sentence whole as one phrase.

### F5 [low] Stale counts and labels
Where: The wording spec section ("it requires these six phrases", followed by seven); E5 ("dropping any one of the bullet's four phrases"); `check.sh` AC2 label (it omits the refspec case, which AC2's text and `refuse.spec` include); AC3's text ("is refused whole (use `git fetch --atomic …`)", while the sentence now says whole only with `--atomic`).
Evidence: the quoted text.
Critique: an executor reading "six" against a seven-phrase spec has to stop and check which is right (lesson z-design/spec-design-correspondence: a check's label says exactly what its command verifies).
Consequences: none.
Recommendation: say "seven" (or the count after F1 and F4), rerun E5's mutant over the current phrases and record it, add "a refspec writing outside `refs/remotes/`" to the AC2 label, and write "refused whole as an `--atomic` fetch" in AC3.

### F6 [low] The harvest calls the same mechanism "one-off" four times, and the lesson it proposes is never written
Where: `harvest.md`, the entries for design-review-001 F3, 002 F2, 003 F1 and 004 F1.
Evidence: each entry reads `one-off: … proposed lesson z-design/promises-name-their-exceptions, to be written by the lead`. `z-nile/skills/z-design/lessons/` has no such file, and `./zn lessons --uncovered c0122` reports every finding covered, so nothing will ask for it again.
Critique: a mechanism found in four rounds is by definition not a one-off. z-design step 3 asks for a new lesson or a new source, and the lead of a prep writes it in the prep. If the author is a subagent, the lead must write it before the prep commit. Otherwise the four rounds' lesson disappears behind a passing `--uncovered`.
Consequences: one lesson file rides in the prep commit, and the four entries name it.
Recommendation: the prep's lead writes `z-nile/skills/z-design/lessons/promises-name-their-exceptions.md`. Rule: a promise the text makes (a command that "succeeds", a fetch that "is accepted") is stated as a positive condition plus one safe form, and is run under every configuration key and on every installed tool version that can change it. Check: "which settings and which installed versions of the tool can make this promised command fail, and was each run?" The four harvest entries then name it as their lesson, and `./zn lessons --check` must pass.

Verdict: approve
