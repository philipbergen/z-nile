# Review 003: f0428 (code mode)
Inputs: 9f340e49d, read as `git diff f7852653c..9f340e49d` and `git diff origin/main...9f340e49d`. No gate and no Go test was run, no review worktree was made, the builder's worktree was not touched. One scratchpad probe ran through `./zn run --time 120` (git and disk behaviour only, no network); each finding says what was run and what was read.

## N1 to N11, E, redaction
- N1 holds for the six allowed commands, with gaps. `mergeOrigin` returns at once (engine/main.luau:392); no other merge, pull, checkout, reset or switch is reachable from `new issue`, `list`, `audit`, `status`, `guesses`, `find` (the others sit in sync, land, fold, unfold, recombine, remap, start, done, approve). `Refresh` resolves `refs/remotes/origin/main^{commit}` once (host/front.go:338), judges that sha (343-348) and checks out that sha (356, 592); it does not know the engine's own sha, so after a killed or half-failed publish it judges whatever the engine last fetched, before any checkout. In a host the caller cannot set or clear `ZN_FRONT_DOOR` (not in `engineEnvKept`, then set by `withEnv`, cmd/zn/front.go:116-120, 195-199). Outside a host the caller's own value passes through (main.go:112) and turns the merge off there: a footgun, not a hole. Gaps: F2 (the engine's `origin/main` is not the ref zn judges), and at this commit no test reaches the `git show <sha>:<doc>` branch (main.luau:1877-1880) or `rememberClaim`'s refusal (455-459).
- N2 does not hold: the engine's PATH is absolute only (main.go:207), zn's own git is not (F1). An absolute entry inside the tracker or the host is still accepted (main.go:207 tests `IsAbs` only): minor. The pins hold: environment config beats every file, the engine passes no `-c` for those keys, and the one git that drops them is fence.sh's own `rev-parse` (lib/fence.sh:29-33). The hooks folder is `.tracker/.cache/nohooks`; `.cache` is refused in every commit and its components are checked for links (host/front.go:327); Prepare deletes nothing, it refuses when the folder is not empty (402-404).
- N3 holds for the file name's case, `merge=`, `diff=`, `[attr]` lines and nested files (host/host.go:683-731); does not hold for comment lines (F5). Not seen, by design: a macro defined in the owner's global attributes file and used by the tracker (that file is trusted). The standing checkout runs with no user config (host.go:740-745, front.go:552, 592).
- N4 holds: Locate judges the disk (host/front.go:212-244), Prepare the fetched main (338-348); paths are quoted (832-880); stdout and stderr both pass the filter (main.go:140-143), C0, DEL, C1, invalid and over-long bytes are escaped and a split sequence is held (cmd/zn/front.go:212-228). Tabs and newlines stay, so piped output keeps its lines and columns. None of the six commands opens /dev/tty; git's own credential and ssh prompts do, and carry no tracker text. Gaps: F7 (bidi and invisible format characters) and F4 (the split sequence and the stderr filter have no test).
- N5 holds for inheritance (the lock is zn's only), does not hold when zn dies first (F3). Signals, read from main.go:161-196: a terminal's Ctrl-C and Ctrl-\ reach the engine once (zn catches and drops its own copy); `kill -INT <zn>` alone is swallowed; TERM and HUP go to the engine's pid only, so its git children are orphaned and run on after the lock is released; Ctrl-Z stops both and the lock stays held (a second zn waits 30 s and names the pid); the exit code is the engine's, 128+n for a signal; stdin is the caller's and no allowed command reads it; after Ctrl-C zn still runs Refresh.
- N6 holds (host/front.go:560-563). N7 holds (338, 552, 572, 592). N8 holds (159-173); side effect: outside any repository, a `.tracker` folder in any folder above (say `~/.tracker`) makes every zn command there exit 4. N9 holds (host.go:614). N10 holds (allowlist by name, cmd/zn/front.go:116-132; `asRefusal`, host/front.go:68-84; a failed mkdir or symlink is worded "git failed").
- N11 holds except one name (F6). Nested `CLAUDE.md`, `AGENTS.md`, `.claude`: no tracker folder of this repository holds a file named so (0 of all `.tracker/` paths at 9f340e49d), so nothing legitimate breaks today. The zip pin and the registry read's lifeline hold (lunepin.go).
- E holds (main.luau:3413-3415). Redaction holds for publish (publish.luau:640-647, 929-931) and not for `status` (F8).

## Findings

### F1 [high] zn's own git still gets the caller's PATH, and git resolves a relative entry inside the tracker
Where: z-nile/go/internal/host/host.go:102-116 (`allowedEnv` keeps PATH as it is), 172-176 (`git -C <dir>`); host/front.go:111, host.go:71-72 (the environment is `os.Environ()`, never `d.env`).
Evidence: (1) the owner's PATH starts with `./bin` (the case round 2's N2 defended against); (2) a pusher adds `bin/ssh`, mode 100755, to the tracker's main: `codeAt` judges links, submodules and names only, and `bin` is not an owned name (host/front.go:740-765); (3) `.tracker`'s own checkout gets it (`zn init` on another machine, or the owner's pull there), and Locate's check of HEAD passes; (4) any `zn list` in the host runs Prepare, whose fetch is `git -C <host>/.tracker fetch` with that PATH: for an ssh address git looks `ssh` up from that folder and runs `.tracker/bin/ssh` as the owner. A credential helper that lives outside git's own folder (Homebrew's `git-credential-osxkeychain`) is reached the same way for https. Verified by run for step 4's git behaviour (`PATH=./bin:$PATH git -C repo fetch ssh://…` ran `repo/bin/ssh`); steps 2 and 3 and zn's environment by reading. `TestARelativePathEntryRunsNothing` changes only `f.d.env`, which internal/host never reads, so it cannot see this.
Critique: the round fixed N2 where the finding pointed (the engine) and left the same cause in the other place that runs git inside tracker content. The tempting fix is a second filter in internal/host.
Consequences: two PATH cleaners would drift; the cleaner must also hold for `CheckHost` and `Init`, which run git in the host; Go's own lookup of `git` already refuses a relative hit, so Refresh (zn's folder is then the worktree) fails closed today and stays so.
Recommendation: one function in internal/host that keeps absolute PATH entries only, called from `allowedEnv`, and `withLuneFirst` calls the same one. Cases: `readEnv` and `writeEnv` given `PATH=./bin:bin::/usr/bin` hold `/usr/bin` only; an end-to-end case whose process PATH (not `d.env`) starts with `./bin` and whose tracker checkout holds an executable `bin/ssh` or `bin/git-upload-pack` marker that must not run. Decide in the same change whether an absolute entry inside `.tracker` is dropped too.
Erred: zz-execute
Upstream: zz-review

### F2 [medium] a tag named origin/main makes the engine read and build on a commit zn never judged, and locks publishing out
Where: z-nile/go/internal/host/init.go:335 (the clone takes every tag); z-nile/engine/publish.luau:652, 918-924 and about 260 uses of the short name `origin/main` in engine/main.luau; host/front.go:338 (zn judges `refs/remotes/origin/main`).
Evidence: (1) a pusher pushes `refs/tags/origin/main` at any commit; (2) the owner runs `zn init` on a second machine, or `git pull` inside `.tracker` (both take tags); (3) git resolves `origin/main` to the tag before the remote-tracking ref, so `zn status` lists the tag's commit, and `new issue` and every status move build on it and push with `--force-with-lease=refs/heads/main:<tag commit>`, which the server rejects: "push rejected after 5 tries: (git's message names the remote, so it is not shown)". Prepare, Refresh and `zn list` see nothing wrong; deleting the tag upstream does not delete the local one. Verified by run for step 3's resolution (after a plain clone `git rev-parse origin/main` gave the tag's commit, `refs/remotes/origin/main` another) and that `git fetch origin main` alone follows no tag; the rejected push by reading.
Critique: N7's rule (the commit judged is the commit used) stops at the front door; the engine resolves the name again by git's short-name rules. Nothing is checked out, so this is a lock-out and a wrong view, not code. The tempting fix is `--no-tags` on the clone alone.
Consequences: `--no-tags` does not cover the owner's own pull or a tracker cloned before the fix, so Prepare must also look; a refusal there needs a way out that names the local ref.
Recommendation: clone with `--no-tags`; in Prepare refuse, with the reason that names it and `git -C <tracker> tag -d origin/main` (or `branch -D`) as the next step, when `refs/tags/origin/main`, `refs/heads/origin/main` or `refs/origin/main` exists (or simply when `git rev-parse origin/main` differs from the judged sha). Cases: a tag pushed before init, a tag fetched after init, each refused and each cured by the printed command.
Lesson: zz-arch/guards-decide-from-the-tools-resolution
Erred: zz-execute
Upstream: zz-review

### F3 [medium] the engine has no lifeline: when zn dies first the lock is gone and the engine runs on
Where: z-nile/go/cmd/zn/main.go:161-196 (`runChild`: a plain child in zn's own process group, signals sent to its pid only); host/front.go:641-650 (an flock that ends with zn).
Evidence: `kill -9 <zn>` while `zn new issue` runs: the kernel drops the lock, the engine keeps publishing; a second `zn` takes the lock at once, its Prepare runs `checkout --detach` in the worktree the first engine still reads, and starts a second engine there. The everyday form: `zn list | head -1` ends zn by SIGPIPE on its first write after `head` leaves (Go's default for a broken pipe on descriptor 1), with the engine still running and no Refresh. Before this round the lock lived exactly as long as the engine. Read, not run. For today's six commands the damage is a garbled read or a skipped refresh; it becomes a real race when a command that writes the worktree is allowed.
Critique: the round moved the lock from the engine to its parent and gave the registry read a lifeline but not the engine. The tempting fix is to run the engine through `RunLifeline` as it is.
Consequences: `RunLifeline` puts the program in its own process group with /dev/null as stdin: a terminal's Ctrl-C and Ctrl-\ then no longer reach the engine, so zn must forward INT and QUIT as well, to the group, which also ends the orphaned git children of a forwarded TERM; Ctrl-Z would stop zn and not the engine; `nohup zn` is already defeated (Notify on an ignored HUP installs a handler and the forward kills the engine) and should be decided in the same change (`signal.Ignored`).
Recommendation: give the engine the lifeline (its own group, killed whole when zn's pipe closes), forward INT, QUIT, TERM and HUP to that group, and skip the forward for a signal that was ignored at start. Cases: zn killed with SIGKILL while a fake engine holds a marker, the engine and its child are gone and the lock is free; TERM to zn ends the engine's child too; the exit code is 128+15.
Lesson: zz-arch/children-need-a-lifeline
Erred: zz-execute
Upstream: none

### F4 [medium] the child runner, the round's centre, has no test
Where: z-nile/go/cmd/zn/main.go:161-196; every test of cmd/zn replaces `d.child` (front_test.go:113, front_review_test.go:83, 203, front_round3_test.go:75, 195).
Evidence: no test file names `runChild`, a signal or 128. These mutants pass the whole suite: forward nothing; return 0 for a signalled engine; pass `nil` for stdin; drop `newTerminalFilter(d.stderr)` (only stdout is asserted, front_round3_test.go:258-264, while `list` and `audit` print tracker file names on stderr); write a split UTF-8 sequence as two invalid halves (no case splits a write). The `git show <sha>:<doc>` read of `status` and `rememberClaim`'s refusal are also untested at this commit (the builder is adding the second).
Critique: N5's and N4's answers are stated in the ticket and proven only through fakes that stand where the code is.
Consequences: a test of `runChild` starts a real process, so it must be bounded and must hold on a marker, not a sleep.
Recommendation: one test that runs `runChild` on a small script: its exit code, a TERM sent to the test's own pid arriving at the script, 128+n, stdin read through; a unit table for `terminalFilter` (a C1 sequence split across two writes, an over-long form, a held tail at Flush) and one stderr case with a control byte in a file name. The claim test being added must also fail when the status branch reads the worktree's file (the claim file holds the old stamp).
Lesson: zz-test/pin-call-site-arguments
Erred: zz-execute
Upstream: none

### F5 [medium] an attributes line that starts with a form feed, vertical tab, NBSP or NEL and then # is a comment to zn and a pattern to git
Where: z-nile/go/internal/host/host.go:685-686 (`strings.TrimSpace`, then `HasPrefix(line, "#")`).
Evidence: `.gitattributes` holding `\f#* filter=lfs` and a file named `\f#x`: git's blanks are space, tab, CR and LF only, so git reads the pattern `\f#*` and sets the filter; Go trims the form feed and skips the line. Verified by run on git's side (`git check-attr` printed `filter: evil` for the form-feed line and `merge: evil` for the NBSP line); Go's side by its definition of space. Today nothing follows from it in a tracker: the standing checkout has no user config, and the six commands hash from stdin and never add, diff or merge. It is the only guard in front of `AddWorktree` (host.go:553-559), which runs with the user's config in the host, so a host that adopts LFS behind such a line is not refused.
Critique: a second reader of git's format that trims more than git does. The tempting fix is to list the extra characters.
Consequences: any hand parser keeps a gap of this kind (quoted patterns, the BOM, the 2048-byte line limit all lean the safe way today, by luck); the check must stay cheap on a tree with many attributes files.
Recommendation: trim only git's four blanks before the comment test, and add the cases (form feed, vertical tab, NBSP, NEL, each with `filter=`, `merge=`, `diff=`); better, refuse a `filter=`, `merge=` or `diff=` token anywhere in the file, comment lines included, which needs no knowledge of git's comment rule.
Lesson: zz-arch/guards-decide-from-the-tools-resolution
Erred: zz-execute
Upstream: zz-review

### F6 [low] the look-alike rule misses the one owned name with a ligature: .conﬁg.luau
Where: z-nile/go/internal/host/front.go:692-726 (`plainName`, `sameName`).
Evidence: `.con` + U+FB01 + `g.luau` has 11 runes against 12, and `EqualFold` folds rune by rune, so `sameName` says no; this disk opens it as `.config.luau` (verified by run on the scratchpad's APFS volume: full case folding; the long s and the Kelvin sign also open the owned names and are caught; a combining mark and a zero-width space do not, and are refused anyway). No other owned name holds ss, ff, fi, fl or st. No allowed command starts Lune on a path through the links, so nothing reads the file today.
Critique: a heuristic chases the disk's rule one case at a time.
Consequences: refusing by shape instead removes the class but refuses a top-level name with any non-ASCII character.
Recommendation: refuse a top-level name that is not plain ASCII (project folders are, by the registry's grammar; README.md and .gitignore are), keep the folded compare for the three names refused at any depth, and add the ligature case.
Erred: zz-execute
Upstream: none

### F7 [low] the terminal filter passes bidi and invisible format characters
Where: z-nile/go/internal/host/front.go:888-905 (`terminalSafe`), 832-852 (`shellQuote`'s plain and single-quoted forms).
Evidence: a ticket title with U+202E or U+2066 to U+2069 reaches a terminal that renders bidi (Terminal.app, VTE, Konsole) and shows text in another order than its bytes; U+200B, U+FEFF and U+2028 pass too. Read, not run. It can mislead the reader of `zn status`; it cannot run or write anything.
Critique: the filter's rule is "control bytes", and these are format characters.
Consequences: escaping every Cf character breaks emoji joined with U+200D and marks right-to-left text needs.
Recommendation: escape U+202A to U+202E, U+2066 to U+2069, U+200E, U+200F, U+061C, U+2028 and U+2029 as `\uHHHH` in `terminalSafe` and treat them as "control" in `shellQuote`; one case each.
Erred: zz-execute
Upstream: none

### F8 [low] a failed publish now hides its cause and prints advice that wedges the standing worktree; status still prints git's words
Where: z-nile/engine/publish.luau:640-647, 929-931; engine/main.luau:1265-1270 ("PICKMAN_PUBLISH=0 creates it locally instead"), 1552 (`sh.git` fetch in `originPaths`), 1866-1870; cmd/zn/front.go:119 (`PICKMAN_PUBLISH` kept); host/front.go:583-585.
Evidence: (a) with no network or a refused credential, `zn new issue` says only "(git's message names the remote, so it is not shown)": the owner cannot tell an expired login from a server rule; (b) following the printed hint, `PICKMAN_PUBLISH=0 zn new issue f x` writes the ticket as untracked files in the standing worktree, and every later command refuses "has files that are not zn's"; `zn status <id> prepared` on a ready design edits tracked files there with the same end; (c) `zn status` offline fails through `sh.must`, which prints git's stderr, the address included. Read, not run.
Critique: the redaction removed the cause with the address.
Consequences: a message that keeps git's words must still lose the address in every form git prints it.
Recommendation: in a host print git's stderr with the address replaced (the effective address is known: replace it and its quoted and slash-ended forms), for publish and for `originPaths`; drop the PICKMAN_PUBLISH hint under `ZN_FRONT_DOOR` and drop `PICKMAN_PUBLISH` from `engineEnvKept`; refuse `status <id> prepared` in the front door until `zn tracker merge` exists. Cases: a rejected push shows the server's line and no address; offline `status` shows no address; the two wedges are refused before the engine.
Lesson: z-design/refusals-name-a-way-out-that-works
Erred: zz-execute
Upstream: none

### F9 [low] after main is rewound the standing worktree is refused with advice to push the dropped commits back
Where: z-nile/go/internal/host/front.go:572-578 (unchanged rule of round 2, now on the judged sha).
Evidence: a pusher adds spam commit X (it is data); the owner's zn moves the worktree to X; the owner removes X with a force-push; the next command refuses "holds commits that are not on the tracker's main (X) … git -C … push origin HEAD:main sends them", which would publish X again. The same after any pusher's force-push. Read, not run.
Critique: the rule cannot tell the owner's own commit from a commit that used to be main.
Consequences: zn must remember where it put the worktree, in a place a pusher cannot write.
Recommendation: record the sha zn last moved the worktree to in a local ref (`refs/zn/standing`); when HEAD is that sha the move is safe whatever the ancestry; keep the refusal for any other HEAD. Cases: rewind then move; a hand-made commit still refused.
Erred: zz-execute
Upstream: zz-review

### F10 [low] two tests still depend on how fast a shell starts
Where: z-nile/go/internal/lunepin/lunepin_test.go:184-196 (`TestCommandStopsTheWholeGroup`: 0.5 s for /bin/sh to start and write its pid file, else `t.Fatal`); z-nile/go/cmd/zn/front_review_test.go:286-316 (`TestTheRegistryReadIsBounded`: a fixed 5 s on every run).
Evidence: the second was raised twice in this round because a loaded gate failed it; the first has the same shape with a tenth of the bound.
Critique: both hold on a clock, not on the marker they already write.
Consequences: none.
Recommendation: start the command, wait for the pid file (bounded at 30 s), then cancel the context; the registry test needs `projectHomes` to take a context, or a timeout that starts when the marker appears.
Lesson: zz-test/hold-on-markers-not-sleeps
Erred: zz-test
Upstream: none

### F11 [low] leftovers
Where: z-nile/go/internal/lunepin/lunepin.go:56; z-nile/go/cmd/zn/main.go:136-139, 144-146, 195; z-nile/go/internal/host/front_round3_test.go:349, 355, 374.
Evidence: the `.rokit` skip under a binary pin is dead as a guard (the digest decides and nothing is run), which is why no mutant catches it: remove it. `child == nil` falls back to exec, which drops the lock, the filter and the refresh: no production path sets it nil, so it should fail instead. A `Wait` error that is not an exit status is reported as "cannot run … noexec mount" and skips Refresh. The test list holds `K/x` and skips it in the loop; `var _ = regexp.MustCompile` keeps an unused import.
Critique: small, each one line.
Consequences: none.
Recommendation: remove or correct each.
Erred: none
Upstream: none

Verdict: changes
