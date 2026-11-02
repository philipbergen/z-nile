# Review 004: c0122 (design mode)
Inputs: worktree `prep-fence-accepts-empty-fetch` at 0d4323b4, plus its uncommitted `c0122.md`, `check.sh`, `acceptance/{fetch,refuse,wording}.spec.luau`, `design-review-00{1,2,3}.md`, `design-refute-00{1,2,3}.md` and `harvest.md`; `z-nile/lib/fence.sh`, `z-nile/lib/git-hooks/reference-transaction`, `SETUP.md`; `./zn lessons --when design`.
Dropped from design-review-003: F1, F2, F3, F4. Their fixes are in the document and the specs, and on git 2.54.0 they hold: the safe form with every prune and tag setting on, the `PINS` list, the refspec case, the headers and the `empty` row. The new finding is in the mechanism that the fixes and the positive rule rely on (what one `git fetch` sends to the hook), not in any one fix.
Runs (every command time-bounded; fixtures and a `--no-hardlinks` clone of the worktree with the prep files copied in, all in one `mktemp -d` folder, deleted afterwards). This machine has two gits: `/usr/bin/git` and Xcode.app's are `2.54.0 (Apple Git-157)`, and the Command Line Tools' (`/Library/Developer/CommandLineTools/usr/bin/git`) is `2.50.1 (Apple Git-155)`. `xcode-select -p` is Xcode.app here.
- `./zn promote-check c0122`: OK.
- In the clone, `fetch` and `refuse` with git 2.54.0: 11 passed, 0 failed.
- The same, with `PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH` (git 2.50.1): 8 passed, 3 failed (F1).
- Hand fixtures, fenced by this worktree's `pickman_fence` through the specs' own `fenced.sh` script, run on both gits: plain fetches, and the same with `--atomic` (F1).

### F1 [high] On git 2.50.1, the git that SETUP.md's `xcode-select --install` provides, three AC2 cases are red, and the Ref guard sentence's "refused whole" and "an empty one included, is refused" are false
Where: Design item 1 (the new Ref guard sentence); The end-to-end specs (`refuse.spec` cases 1, 3 and 5); AC2 ("each refused whole: nothing moves"); Unknowns & experiments (E1 to E8, all on git 2.54.0 only); Rules rows "a spec run's fetch with nothing new is refused …", "a fetch that would follow a tag … is refused whole", "a remote whose own refspec … is refused whole"
Evidence: `SETUP.md` line 13 installs git on macOS with `xcode-select --install` (the Command Line Tools), and on Linux from distro packages. It names no minimum version. The Command Line Tools' git on this machine is 2.50.1. With it first on `PATH`, in the clone:
```
FAIL refuse.spec.luau :: AC2: a spec run's fetch is refused whether or not anything is new, and moves nothing
  expected "brings=true bringsOk=false nothing=true nothingOk=false unmoved=true", got "brings=true bringsOk=false nothing=false nothingOk=true unmoved=true"
FAIL refuse.spec.luau :: AC2: a check.sh flow's fetch that follows a new tag is refused whole, and moves nothing
  expected "mainKept=true noTag=true ok=false said=true sync=true", got "mainKept=false noTag=true ok=false said=true sync=true"
FAIL refuse.spec.luau :: AC2: a remote whose own refspec writes outside refs/remotes/ is refused whole, flags or not
  expected "mainKept=true noUp=true ok=false said=true", got "mainKept=false noUp=true ok=false said=true"
8 passed, 3 failed
```
The hand fixtures show the same thing. A tag-following fetch and a refspec fetch both exit 128 with the guard's message (`fatal: ref updates aborted by hook`), but `refs/remotes/origin/main` has already moved. On 2.50.1 a plain fetch updates each ref in a transaction of its own, so the guard refuses only the tag or `refs/heads/up/main` update, after the remote-tracking ref is written. A spec run's nothing-new plain fetch exits 0, because 2.50.1 starts no transaction at all and the hook never runs. A pruning fetch is refused with both refs kept on both gits. On 2.54.0 every case is one transaction, which is the only thing E1 to E8 measured. So the Problem's "git still runs a ref transaction with no refs in it", the sentence's "refused whole", and "during a spec run every update, an empty one included, is refused" all describe how one git version batches a fetch, not what the guard does.
`--atomic` behaves the same on both gits. With `fetch --atomic` (`PINS` applied):
- a spec run's nothing-new fetch: 128 (an empty transaction is sent, as the Problem describes);
- a check.sh flow's nothing-new fetch: 0;
- a tag-following fetch: 128, `origin/main` kept;
- `--atomic --no-prune --no-prune-tags --no-tags`: 0, follows `main`;
- that same form with the `up/*` refspec: 128, `origin/main` kept.
Critique: these specs exist to pin "what git sends through the fence", so they rest on git's transaction shape. That shape changed between 2.50.1 and 2.54.0, and the design ran one version. Once promoted, `refuse.spec` turns `z-nile/check.sh --full` red with no code change, on a machine set up exactly as SETUP.md says (and on distro gits, which are older still). A check author on such a machine who reads "refused whole" and sees `origin/main` move after a refused fetch has been told something false. This is lesson zz-test/specs-set-host-markers-explicitly again, with the git version as the host fact; z-design/accepted-risks-checked-and-decided asks for the premise to be checked against SETUP.md's supported hosts. There are two tempting fixes:
- Drop `mainKept` from the tag and refspec cases, and accept either outcome for the spec-run nothing-new fetch. That lets M2 (an empty transaction accepted in spec runs) survive on every git, and keeps a false "whole" in the text.
- Skip the cases on an old `git --version`. That leaves the rule unpinned exactly where it differs.
Consequences:
- Taken one step further, the fix is to remove the version from the question. Make the specs and the promised command use `--atomic`, so every git runs one transaction for the whole fetch, tag backfill included. That changes item 1's text and AC3's phrases (the safe form gains `--atomic`; "refused whole" holds for that form).
- The sentence then needs a clause for a plain fetch: without `--atomic`, an older git can write the `refs/remotes/` part before it refuses the rest. Otherwise the text overpromises again.
- The spec-run case uses `--atomic` for its nothing-new fetch, so M2 is killed on both gits. A plain nothing-new fetch in a spec run changes nothing on any git (2.50.1 runs no hook), so the sentence's "an empty one included" belongs to the atomic form only.
- `--atomic` needs a git that has it, and tag backfill inside it. I recall these as git 2.31 and 2.36, but I didn't run either. The design should name the oldest git it ran and say in SETUP.md (or in the sentence) what it requires.
- If the user would rather require a newer git in SETUP.md and keep plain fetches, that is a new setup requirement for every contributor, and the user's call.
Recommendation:
- Item 1: change the safe form to `git fetch --atomic --no-prune --no-prune-tags --no-tags origin`, and say "refused whole" only of an atomic fetch. Add: "without `--atomic`, git before <the measured version> refuses only the offending refs and may already have moved `refs/remotes/`". Mirror this in AC2's text, AC3's phrases and Usability.
- `refuse.spec` cases 1, 3 and 5 and `fetch.spec`'s nothing-new and safe-form fetches: pass `--atomic` (for example in `fetch()`'s argv after `"fetch"`). Keep one plain (non-atomic) nothing-new and one plain bringing fetch in AC1, whose `ok` holds on every git.
- New experiment E9: run `fetch` and `refuse` on both gits on this machine (`PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH` gives 2.50.1). Record that each passes on both, and that M1, M2, M5, M9, M12, M14 and M16 still fail their rows on both. Note that without `--atomic` M1 is unkillable on 2.50.1, which is harmless there because the bug doesn't exist on that git.
- Record the oldest git the specs ran on. Either state the requirement in SETUP.md's git row, or escalate to the user if the plain-fetch route (a minimum git ≥ 2.51 for everyone) is preferred.
- Add a `Prep finding` sentence noting that the Problem's empty transaction is the batched-fetch behaviour of newer git. Don't rewrite the captured Problem.
Lesson: zz-test/specs-set-host-markers-explicitly; z-design/accepted-risks-checked-and-decided. A candidate for the lead, which repeats design-review-003 F1's mechanism a fourth time and so should probably be folded into the proposed z-design/promises-name-their-exceptions: a spec or rule text that pins what an external tool does is run on every tool version the supported hosts in SETUP.md install (at least the oldest one on hand), or the version is pinned. Check: "which installed versions of this tool did the cases run on, and does SETUP.md's install path give one of them?"

### F2 [low] The tag case still depends on the host's `remote.origin.tagOpt`, which `PINS` doesn't name, and an empty `-c` value doesn't reset it
Where: `refuse.spec` `PINS` (lines 45 to 54) and the tag case (line 165); Design › The end-to-end specs ("the host's git configuration never decides a case")
Evidence: in the clone, `GIT_CONFIG_GLOBAL=<file: [remote "origin"] tagOpt = --no-tags>` turns the tag case red (`got "mainKept=false noTag=true ok=true said=false sync=true"`; 6 passed, 1 failed). Design-review-003 F2 recommended `-c remote.origin.tagOpt=` for the plain fetches. That doesn't work: with that file and a new tagged commit, `git -c remote.origin.tagOpt= fetch origin` still fetched no tag, so an empty value doesn't restore git's default tag following. A global `remote.origin.*` is rare, which is why this is low, but the Design's sentence promises that the host config decides no case.
Recommendation: make the tag case independent of `tagOpt`. Either pin `-c remote.origin.tagOpt=--tags`, which is still a fetch that writes into `refs/tags/` and is refused, and reword the case and its row as "a fetch that writes a tag". Or keep default following and narrow the Design sentence to the keys `PINS` names. Run the chosen form with the `--no-tags` global file, and with M14.

Verdict: changes
