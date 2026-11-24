# Review 004: f0428 (code mode)
Inputs: 811278d9c, the round-4 answer to `review-003.md`. Filed by the builder from the findings the coordinator passed on (the reviewer's own text was not handed over whole); each finding keeps its id, its place and what the review asked.

## P1 to P11
P2, P6, P7, P9 and P11 hold. Q1 to Q8 below.

## Findings

### F1 (Q1) [high] the engine's group is not the terminal's foreground group, so a prompt on /dev/tty stops it and zn hangs
Where: z-nile/go/cmd/zn/main.go about 205 (`Setpgid`).
Evidence: the engine's git or ssh prompts on /dev/tty (an https login with no stored credential, an ssh key with a passphrase and no agent); the kernel stops the whole background group, the lock stays held and Ctrl-C does not end zn. Proven under `script(1)`: all three processes in state T, runChild not returned 4 s after INT. Before round 4 the prompt worked.
Recommendation: when zn's standard input is a terminal, start the engine's group as the terminal's foreground group (`Setpgid`, `Foreground`, `Ctty`), take the terminal back after Wait with SIGTTOU ignored around `tcsetpgrp`, follow Ctrl-Z, and deliver INT, QUIT and TSTP once (the terminal now sends them to the engine's group itself); zn survives them, refreshes and releases. With no terminal keep the design and start the wrapper with `trap '' TTIN TTOU`, so a prompt fails at once with git's words. Tests under a pty: a /dev/tty read gets its input and exits 0; Ctrl-C at the prompt ends zn promptly with the lock released; with no tty the read fails fast and nothing is left stopped. Also Ctrl-Z then CONT (a helper, `ps` state T, then a marker) and zn's own SIGPIPE (a helper whose stdout the test closes). A killed watcher leaves the engine without a lifeline: record it as accepted.

### F2 (Q2) [medium] the attributes search indexes the original text with offsets found in its lower-cased copy
Where: z-nile/go/internal/host/host.go about 752-769.
Evidence: `strings.ToLower` changes byte lengths (an invalid byte becomes three, Ⱥ grows, the Kelvin sign shrinks), so one non-ASCII byte before the line hides the setting: `"#\xff\n* filter=x\n"`, a Latin-1 comment before `*.bin filter=lfs`, `"# Ⱥ\n* filter=x -text\n"`, four Kelvin signs before the line.
Recommendation: search the original bytes with ASCII-only case folding; add those cases; compare zn's verdict with `git check-attr` for a table of files.

### F3 (Q3) [low] redaction misses the forms git prints for ssh and file addresses
Evidence: for `git@host:path` git prints `host:path`; for `ssh://git@host/path`, `ssh://host/path`; a `file://` address prints as its bare path.
Recommendation: also replace each address with its user part removed, and a file address's path; test with a fake ssh, no network.

### F4 (Q4) [low] `status <id> prepared` passes the front door behind an option that takes a value
Evidence: `status f0001 --x y prepared`, `status --project up f0001 prepared`.
Recommendation: refuse when any argument after `status` is `prepared`, and refuse in the engine under ZN_FRONT_DOOR as well (its parser is the authority).

### F5 (Q5) [low] the PATH cleaner's root rule fails open
Evidence: it compares lexically and case-sensitively; an entry whose tail does not exist is not resolved; `readRepo` and `CheckHost` pass no roots; `lookGit` falls back to the bare name `git`.
Recommendation: compare by identity (`os.SameFile` over the resolved entry and its ancestors against each root), resolve the longest existing prefix, pass roots everywhere, and make `lookGit` an error. Tests: another case of the folder, the `/System/Volumes/Data/...` alias, a not-yet-existing tail behind a linked prefix, an absolute entry inside the repository at Locate, the only git being inside the root.

### F6 (Q6) [low] `zn list | head -1` reports an engine error and exits 1
Evidence: an engine that exited 0 with a broken output gives "the engine ended with an error" and exit 1.
Recommendation: an EPIPE copy error with a zero status is exit 141 with no message. Test.

### F7 (Q7) [low] code with no test, and two tests that lean on the network or a clock
Evidence: `if code == 0 { code = 1 }`, the `errNotStarted` message, `Open`'s host root for a tracker, `checkShortName`'s final `rev-parse` comparison alone and its worktree-gitdir file case, the self-kill half of 128+n. `TestARelativePathEntryRunsNothing` starts the real ssh on `example.invalid` (a DNS lookup); `TestAWaitingZnSaysTheHolderIsStopped` trusts a 200 ms wait.
Recommendation: a test each that fails without the code, or remove the code; a stub `ssh` outside the host that writes a marker; poll `ps` for state T.

### F8 (Q8) [low] a pushed tag named `main` starves the engine's own fetch of main
Evidence: `git fetch origin main` fetches the tag, exits 0 and leaves origin/main where it was, so a contended publish never sees the new main. A clone made before round 4 has no `remote.origin.tagopt`.
Recommendation: fetch `+refs/heads/main:refs/remotes/origin/main` in publish.luau and main.luau; test with a tag `main`. For an old clone, set `--no-tags` in Prepare or refuse its absence naming the key. The "another ref named origin/main" refusal's next step names both the local delete and that the tag exists upstream.

Verdict: changes
