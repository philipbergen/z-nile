# Audit C: closing f0427, f0428, c0436, c0179, d0426 (read-only)

Read on origin/main 3e7b197e3 (= the main checkout), 2026-11-24. Paths are repository-relative. Nothing was written in the repository. The commands I ran were `./zn capture|guesses|rounds|status|audit|approve --check|lessons --check-review|--uncovered`, plus git and `gh pr view`. No gate and no specs were run.
c0179 and c0436 were audited by two sonnet subagents (on the light model). Their full notes are beside this file, in `audit-C-c0179.md` and `audit-C-c0436.md`. Their main claims are condensed in sections C and D, and I spot-checked those claims against the tree.

## 0. Cross-cutting findings (apply to all five)

1. **The pipeline has no way to close code that is already on main.** `./zn done` takes a raft id only (z-nile/skills/zz-rules/SKILL.md:106). Before it lands, it needs all of the following:
   - a readied raft (`ready` needs `design: ready` and a `check.sh` with a check, SKILL.md:84);
   - finished layers;
   - `./zn trace <R> --check`;
   - a resolved `final-review-NNN.md`;
   - the raft's `check.sh`.

   `trace --check` takes the code column from the source files *the stack changed*. A closing raft would change no source file, because the code merged in #738/#746/#733/#747/#753/#765/#791/#713/#745/#761. Its code cells must then be `none` (z-nile/engine/trace.luau:84-86, 1150-1155). The idea = design = test = code trace that zz-review's Final mode promises (SKILL.md:130-136) therefore cannot cite the merged code mechanically. Two honest options are open, and the owner picks one:
   - (a) Accept a closing raft whose final review judges the merged commits by hand, with code cells `none`, and say so in each trace.
   - (b) First capture and build a small engine change: a "closing raft" whose trace cites code at named main commits.

   Nothing in the engine or the skills mentions closing hand-merged work (`git grep -i "retroact|already merged|outside the pipeline"` over z-nile/engine and z-nile/skills: no such rule). This is the first thing to settle, because it decides the size of every item below.
2. **A pushed guess is never changed or removed** (zz-rules SKILL.md:86). The approval covers the whole `guesses.md`. Wherever most guesses are about the unbuilt part, the owner must still approve all of them on the closing ticket. The alternative is the reverse split: a new ticket takes the built part and closes, and the old id keeps the unbuilt part and its guesses. That matters for f0427 (14 guesses, 13 about unbuilt slices) and f0428 (18). For f0427 the reverse split costs a move of its sequestered specs: `embed.spec.luau` and `cache.spec.luau` sit in `f0427/acceptance/` and are promoted to `tests/acceptance/f0427`. They can move to a new ticket's folder in its prep, before ready.
3. **Not one of the five has a design review that the engine counts as answered and settled.**
   - f0427/f0428: one shared round in the old format. Its F1-F24 are list items, not `### F` headings, and it has no `Verdict:` line. `./zn rounds f0427 --kind design` says "design-review-001.md has no Verdict line and no findings: fix the file or redo the round".
   - c0179: the same defect.
   - c0436, d0426: none.

   Not one of the five has a final review. Not one of the five has an approval (`./zn approve --check` prints "<id> has no approval" for f0427, d0426, c0436 and c0179; for f0428 it fails on its guesses file, see B).
4. `./zn audit`: 0 errors, 0 warnings (nothing about any of the five). `./zn status`: f0427, f0428 and d0426 are `new`, c0179 is `preparing`, and c0436 is `new`.
5. Memory rules that apply: "never narrow captured scope" (every split below needs the owner's explicit yes, recorded as a `Scope decision (user, date)` line), "full gate only at merge", and "one heavy run at a time".

---

## A. f0427: Zn one go app any repo

Doc: z-nile/.tracker/issues/f0427/f0427.md (362 lines).
- Frontmatter: `design: reviewed`, `risk: risky`, `status: new-…`, no raft.
- Merged PRs:
  - #738 8658df5f4, step 1: 21 files, +2,193.
  - #746 016474fdf, step 2: 12 files, +2,234/-160.
- Tracker-only merges: #730, #735, #736, #741.
- Code on main: z-nile/go/cmd/zn (main.go 457, front.go 260, init.go 181, lune.sum 11), z-nile/go/internal/payload (payload.go 329, safe.go 458, sum.go 86, embed_on/off), z-nile/go/cmd/znpack (109) and z-nile/lib/znbuild.sh.

### A1. Captured outcomes and decided lines

The capture (6ceb1c2bb) is one sentence: "zn is one Go app that runs in any repository, first omarchy on Linux". Every Solution bullet was added in design. They are judged here as the contract, as zz-review item 11 does.

| # | outcome (f0427.md line) | state | proof / where | in gate? |
|---|---|---|---|---|
| S1 | one program `zn`, installed once, runs on Linux and macOS, no Lune/Luau/Rojo (44) | **partly**: macOS build runs with `PATH=/usr/bin:/bin`; the linux/amd64 build is cross-built and its payload checked; never run on Linux; **no install, release or upgrade path** (step 12 not built; owner 2026-11-24: "This is why I want zn to be a go executable with its own lifecycle") | cmd/zn/main.go:61-121, internal/payload; `acceptance/embed.spec.luau` (AC1) | Go tests yes (check.sh:323 `go test ./...`); embed.spec **unpromoted** |
| S2 | `zn init` creates `.tracker` and adds it to `.git/info/exclude`, no tracked file changed (45) | **delivered, in f0428's form**: a clone of a remote tracker, not f0427's local bare origin; it also adds `.worktree/` and `.cache/`, which f0427 §12 says it should not | internal/host/init.go, cmd/zn/init.go; cmd/zn/init_test.go, internal/host/init_test.go | yes (Go) |
| S3 | every ticket, raft, claim, approval, board, setting and skill under `.tracker` (46) | **partly**: tickets and claims only, through the six host commands (front.go:37-50); approvals, the board, settings.toml and skills: not built | cmd/zn/front_test.go:268 `TestTrackerCommandsWorkFromAHostAndLeaveItUntouched` | yes |
| S4 | zn carries every skill; init writes them under `.tracker/skills/` (47) | not built | none | none |
| S5 | `zn work` prints the skill paths (48) | not built (`work` is refused in a host, main.go:73-82) | none | none |
| S6 | every tracker change (capture, design, raft, ready, stop, approve, done) under `.tracker`, no host commit (49) | **partly**: `new issue` and `status` only | front_test.go:268 | yes |
| S7 | the gate runs `test.command` from `.tracker/settings.toml` and refuses without one (50) | not built (no `zn gate`, no internal/settings) | none | none |
| S8 | only `zn`, the AI CLI, git and gh (51) | not built / not proven (the design adds bash, perl and uuidgen: S1 under Open, unruled) | none | none |
| S9 | refuses to start the worker naming a missing program (52) | not built (`zn doctor` absent) | none | none |
| S10 | omarchy: one raft through every tracker step (53) | not built | none | none |
| S11 | omarchy: branch, PR, gate, land, done (54) | not built | none | none |
| S12 | the board shows each state; the approval walk records the ruling (55) | not built | none | none |
| S13 | the omarchy delivery with no Lune and no pickman layout (56) | not built (OC1) | none | none |
| S14 | after non-delivery commands `git status`, log and branch in the host show nothing (57) | **delivered for init and the six host commands** | front_test.go:268 (Snapshot/Diff empty after each), init tests | yes |
| S15 | the only host commits are raft code (58) | not built (zn makes no host commit at all yet) | none | none |
| S16 | the first packaging may carry the Luau engine (59) | **delivered** (a permission, not an outcome) | internal/payload | yes |
| D1 | Decided 2026-11-21 "fork and pr" (23) | not built (no `zn pr`) | none | none |
| D2 | Decided: each step's acceptance spec is reviewed separately (25) | delivered for steps 1-2, as a process: PR #738's body says so; no review file of it is in the tracker | PR body only | n/a |
| D3 | Decided: take the interpreter, convert to Go steadily, "the conversion has its own ticket" (27) | the packaging is delivered; the conversion is c0447 "Engine to go steadily" (backlog) | | |
| D4 | Decided: "linux we wil get to eventually" (31) | recorded; AC2 stays failing by ruling | check.sh:15 is `exit 1` | n/a |

Count: delivered 4 (S2 in f0428's form, S14, S16, D2); partly 3 (S1, S3, S6); not built 10 (S4, S5, S7-S13, S15, D1).

### A2. Design versus what was built
- **Stale or unbuilt sections:**
  - §1: carries step 1 and step 2 "as built" deviations, which are fine.
  - §2 describes a local bare origin under `$XDG_DATA_HOME/zn/trackers`, never built and superseded by f0428 step 3's remote tracker.
  - §3 (front-door duties), §4 (doctor), §5-6 (host facts, `done --check`), §7 (sequestration), §8 (`zn gate`), §9 (`zn run` in Go), §10 (skills, live, `init --upgrade`), §11 (settings) and §12 (local init): all unbuilt.
  - The f0428 step-4 front door built a different subset, in a different shape: child process, allowlist and data check. §3 says ZN_TOP and ZN_CWD are set, the CPU limit lowered and approve gated; as built, approve is refused in a host and no RLIMIT is set in Go (main.go has no Setrlimit; ZN_ENGINE_CPU is only passed through, front.go:116-125).
  - The Touched modules list `release.sh`, `zn-linux.yml`, `hostmode.luau`, `internal/settings`, `internal/hostfacts` and `internal/bounded`: none exists.
  - The Affected specs (310 over engine paths) apply to step 8, not to what was built.
- **Checked ACs (289-319) against check.sh (14-28):** every AC has a check line, but only AC1 (`embed.spec.luau`) and AC3 (`cache.spec.luau`) name a spec that exists. AC4-AC15 name 12 specs that do not exist (`init`, `tracker-writes`, `frontdoor`, `skills`, `doctor`, `run`, `gate`, `sequester`, `donecheck`, `commit`, `prstate` and `board.spec.luau`; `git ls-files z-nile/.tracker/issues/f0427/acceptance` holds only embed, cache and lib/zn.luau). AC2 is a hard `exit 1` (check.sh:15).
- **Reviews:**
  - Design: `design-review-001.md` (Fable 5.2, F1-F24, one round covering f0427 and f0428), answered "fixed" for all of them in `design-refute-001.md`. No round 2 checked the answers. It is unparseable by `rounds` (see 0.3), and `lessons --uncovered f0427` says covered only because it parses no findings.
  - Code: the step 1/2 code reviews ran (PR bodies) but no `review-NNN.md` was filed.
  - `rounds --kind code` and `--kind final`: "no review yet … at most 9".
- **Open to the human (350-362), verbatim and short:**
  - Q1 "Who is the one user?"
  - Q2 "How does code reach omarchy: … fork … or … push access?" Answered by the Decided line at 23, but the bullet was not marked ruled.
  - Q3 "Is carrying the Luau engine … acceptable as the first packaging?" Answered at 27, not marked.
  - Q4 "Where are the release binaries published?"
  - Q5 "Which test command gates omarchy work?"
  - S1 "Do you accept the sentence gaining 'bash, perl and uuidgen'…?"
  - S2 "Does [the bare origin in ~/.local/share] satisfy the sentence, or must it stay inside .tracker?" This is moot now (f0428 step 3 made no local bare origin).
- **Guesses:** 14 (G1-G14), not approved. G1 (the embedded Lune) and G7 (refuses where z-nile/engine/main.luau exists) concern the built part. G7 is not built: `zn init` has no pickman refusal (cmd/zn/init.go; a repository like this one is left alone by `Locate` instead, front.go). G2-G6 and G8-G14 concern unbuilt slices.

### A3. Smallest honest split
- **Closes as f0427 (or as a new ticket under 0.2's reverse split): "zn, a Go program that carries the engine and its runtime, from a verified cache".**
  - Covers: S16, S1 restated as "on macOS arm64 with no Lune; a cross-built linux/amd64 binary carries the pinned Linux Lune" (AC1), the cache hardening (AC3), and D2-D4.
  - Specs: `embed.spec.luau`, `cache.spec.luau` and the payload Go tests.
- **New ticket 1, working title "zn installs and upgrades itself":** the owner's 2026-11-24 words. Outcomes:
  - S1's "installs once", with release packaging for four platforms (step 12, Q4);
  - an install path such as `~/.local/bin/zn`;
  - `zn version` lifecycle and upgrade;
  - `zn_version` recorded in the tracker, with an older binary refusing (§10);
  - the Linux proof (AC2, under D4's "later").
- **New ticket 2, working title "zn delivers a raft in a host repository".** Outcomes:
  - S3-S13 and S15 (the parts not built by f0428 step 4);
  - D1;
  - §3 front-door duties: approve's terminal gate and the CPU limit;
  - §4 `zn doctor`, §5-6 host facts and `done --check`, §7 sequestration, §8 `zn gate`, §9 `zn run` in Go, §10 skills and `zn live`, §11 settings;
  - AC4-AC15 with their 12 unwritten specs, OC0 and OC1;
  - Q1, Q5 and S1 from Open.
  - It overlaps the unbuilt part of f0428 (B3). Those two remainders should be one ticket, or two with `depends_on`, decided together.
- **Cannot split cleanly:**
  - S1 (one program, Linux and macOS, installed once) is half built. It has to be reworded into the built half (runs on macOS without Lune) and the remainder (installed and proven on Linux).
  - S14 is delivered only for the commands that exist. Its sentence "after any sequence of zn commands" holds for the remainder too, so the remainder must restate it.
  - G7 (pickman refusal) is a guess about built code that the code does not honour.

### A4. What `./zn done` refuses today, and the work to get there
- Today: no raft, so `done` has nothing to take. `approve --check`: "f0427 has no approval". `design: reviewed`, not ready, so `ready` would refuse. check.sh has 13 of 15 lines that fail (12 missing specs, AC2 `exit 1`). No final review. No trace.
- Work:
  1. Owner rulings: the split and the scope decision; the 0.1 closing mode; Q2/Q3 marked ruled; S2 dropped as moot.
  2. Doc rewrite: Problem and Solution cut to the closable part, with `Scope decision (user, …)` lines; Design keeps §1 and the step 1-2 as-built text; §2-§12, Touched, Affected specs and Rules rows for unbuilt slices move to the new tickets; the "What a green AC1 and AC2 still do not prove" list is kept.
  3. check.sh: AC1 and AC3 only. These sequestered files may change in prep, before ready.
  4. Capture the two new tickets (z-idea): about 30-60 lines each, plus the text moved over.
  5. A design round on the cut design (risky: cap 9).
  6. A raft. The light path is ruled out (`risk: risky`).
  7. Ready and start; finish a layer carrying only docs; the trace skeleton; a final review over #738+#746 (about +4,400 lines); answers.
  8. The owner approves all 14 guesses (0.2) or the reverse split is used.
  9. `./zn done` promotes `embed.spec.luau` and `cache.spec.luau` into the gate.
- **Risk to check before promoting:**
  - These specs build zn with the Go cache and extract Lune. Their cost per gate run (memory: fast specs) was never measured here.
  - embed.spec's real-Linux-zip case prints SKIPPED off CI (f0427.md:255).
  - Promoting them adds a `znbuild.sh` build to every gate that selects them.

### A5. Estimate and risks
- About 250-350 doc lines moved or cut in f0427.md, 13 check.sh lines removed, and 2 captures of about 60 lines each.
- Review rounds: 1-2 design rounds and 1-3 final rounds over about 4,400 merged lines.
- Risks:
  - closing a `risk: risky` ticket on code reviewed only in PR bodies: a first filed review of about 4,400 lines may find real defects, and those land as follow-up code;
  - S1 is still open on Linux;
  - G7 contradicts the built code;
  - the promoted specs' gate cost.

---

## B. f0428: Tracker in its own repo

Doc: z-nile/.tracker/issues/f0428/f0428.md (388 lines).
- Frontmatter: `design: reviewed`, `risk: risky`, `depends_on: [f0427]`, `status: new-…`.
- Merged PRs:
  - #733 bed3b05b2, step 1, +2,009;
  - #747 fa896824e, step 2, +2,557/-49;
  - #753 09745b7ac, step 3, +2,467;
  - #765 526a1b431, step 4, 50 files, +7,387/-89.

  In total about 14,400 lines, mostly z-nile/go/internal/host (host.go 947, front.go 1,006, init.go 609, roles.go 481, remote.go 344, unusual.go 133, plus tests), cmd/zn/front.go and init.go, and internal/lunepin.
- **The folder has no `acceptance/`**, yet check.sh names `$A/*.spec.luau` for 9 of its 10 lines.

### B1. Captured outcomes and decided lines

The capture (86c3b8fbe) is one sentence: "The tracker lives in a separate repository checked out at .tracker".

| # | outcome (f0428.md line) | state | proof | in gate? |
|---|---|---|---|---|
| S1 | one setup command, given the tracker address, works out the fork and clones to `.tracker` (46) | **delivered** | internal/host/init.go, roles.go; cmd/zn/init_test.go:229 `TestInitRunsEndToEndInGo`, internal/host/init_test.go, roles_test.go | yes (Go) |
| S2 | reads and writes every item only in the tracker; commits and pushes only to it (47) | **partly**: for `new issue`, `list`, `audit`, `status`, `guesses`, `find` (front.go:37-50); everything else is refused | cmd/zn/front_test.go:268 | yes |
| S3 | appends `.tracker`, `.worktree/`, `.cache/` to `.git/info/exclude` (48) | **delivered** | init.go; init tests | yes |
| S4 | in the host's tree zn writes only under those three (49) | **delivered for init and the six commands**; no delivery command exists | front_test.go:268, `TestLocateWritesNothing` (internal/host/front_test.go:228) | yes |
| S5 | fetches default without tags; branch from `refs/remotes/origin/<default>` (50) | **library only**: `FetchDefault`, `AddWorktree`, `FetchAndWorktree` (host.go:682-746), Go-tested; no command uses them | host_test.go:238 `TestSnapshotDelivery` | yes |
| S6 | one branch and worktree per ticket (now per raft, S1 under Open) under `.worktree/`, no zn path in its commits (51) | library only (worktree); no commits, no `zn commit` | same | yes (partial) |
| S7 | pushes only to the fork (52) | not built | none | none |
| S8 | the host `.git` write list (53) | **library and snapshot**: `Snapshot`/`Diff`/`Allowed` (host.go:624); the push half is not built | TestSnapshotDelivery | yes (partial) |
| S9 | moves no `refs/heads`/`refs/tags` it did not create (54) | delivered for what exists (fetch and worktree) | TestSnapshotDelivery | yes |
| S10 | only `origin/<default>` and `<fork>/<branch>` remote refs move (55) | partly (the fetch half) | same | yes |
| S11 | code reaches the host only by a PR the owner asks for, never merged (56) | not built (`zn pr` absent) | none | none |
| S12 | after setup and any command: status, diff and default branch unchanged (57) | **delivered for init and the six commands** | front_test.go:268, init tests | yes |
| S13 | every host worktree resolves the one tracker (58) | **delivered** (`Locate`) | internal/host/front_test.go:200 `TestLocateResolvesTheOneTrackerFromEveryFolder` | yes |
| S14 | the tracker repository is public on GitHub under the owner's account (59) | not built / owner's act (init's walkthrough tells the user to create it; README says it is public); OC1 | init.go walkthrough | n/a |
| D1 | "fork and pr" (23) | not built (no `zn pr`) | none | none |
| D2 | "clone layout should be completely irrelevant" (25) | **delivered** (`Roles`, no names) | roles_test.go `TestRolesNamesNeverDecide` | yes |
| D3 | the user names the tracker repository; init walks them through it; never `gh repo create` (27) | **delivered** | cmd/zn/init_test.go:23 | yes |
| D4 | a fork with no upstream: `refs/zn/upstream/<branch>` (29) | **delivered** (library: `UpstreamRef`; the fetch itself is for a later step, per 118) | roles_test.go | yes (partial) |
| D5 | the ignore line goes in `.git/info/exclude`; `--gitignore` writes it uncommitted (31) | **delivered** | init tests | yes |
| D6 | zn never runs the host's own tests until that has been tested (33) | delivered trivially (nothing runs them) | none needed | n/a |

Count: delivered 9 (S1, S3, S4, S9, S12, S13, D2, D3, D5); partly or library-only 7 (S2, S5, S6, S8, S10, D4, D6); not built 4 (S7, S11, S14, D1).

### B2. Design versus what was built
- **The Design is layered.** The original design (lines 64-112, 203-235) is followed by "As built" steps 2, 3 and 4 with review rounds 1-6 (114-189), "Open before a tracker strangers push to" (191-200) and "Left for step 4b and later" (201).
  - The original text still describes unbuilt parts as if current: claims and publishing through `zn tracker merge`, the raft host branch, `zn pr`, recovery, the scan, `zn init` steps 5-7 (re-pointing an f0427 tracker, adding a project and its `[host.<name>]` table, scan hooks, printing the board path) and Remotes in settings.
  - "This replaces the design's `--upstream` default" (203) and the old `zn init` list (207-219) contradict the as-built step 3.
  - Implementation steps 4-9 (351-357), including the new step 8b "No links at all", are not built.
- **Checked ACs (323-335) against check.sh (14-23):**
  - AC1 and AC2 were amended in the doc to "(proven in Go tests …)", but check.sh still runs `$A/init.spec.luau`, which does not exist. AC1 and AC2 therefore fail.
  - AC3 (`resolve.spec`), AC4 (`clean.spec`), AC6-AC10 (`raftbranch`, `pr`, `scan`, `machine2`, `recover`): none of the specs exists.
  - AC5 runs `go test ./internal/host -run TestSnapshotDelivery`, which exists, but proves only the fetch-and-worktree half of "across a fixture delivery".
  - The doc's Test plan names a `snapshot.spec.luau` that does not exist.
  - So 9 of 10 check lines fail today on a missing file.
- **Reviews:**
  - Design: f0427's `design-review-001.md` (shared, unparseable). `./zn rounds f0428 --kind design`: "no review yet; run design review round 1 of at most 9".
  - Code: `review-003.md` (step 4, 12 headings, step lines ok) and `review-004.md` (F1-F8, "no step lines": `lessons --check-review` refuses it). Neither has a refute file. The answers live in the doc's as-built round 4 and 5 bullets. `./zn rounds f0428 --kind code`: "answer review-004.md in refute-004.md".
  - The round-6 narrow verification (T1-T9) and the step 1-3 code reviews (PR bodies of #733, #747 and #753: "code review and separate test review, then an answers review, then a second fix round") were never filed.
  - There is no harvest.md: `./zn lessons --uncovered f0428` lists 19 findings (review-003 F1-F11, review-004 F1-F8).
  - The code reviews also sit in the issue folder, not on a raft.
- **Open to the human (371-387), verbatim and short:**
  - Q1 "Who is the one user?"
  - Q2 "How does code reach omarchy …?" Answered by the Decided line at 23, not marked.
  - Q3 "Is carrying the Luau engine … acceptable …?" Answered on f0427, not marked.
  - Q5 "Should tracker changes go straight to the public tracker's main?"
  - Q6 "What may omarchy's maintainers see?"
  - Q7 (partly answered) "Which test command gates omarchy work …?"
  - Q8 "Should the tracker's commits carry your real author email?"
  - S1 "Do you accept 'ticket' becoming 'raft' in those sentences?"
  - S2 "Does [a person types `zn pr`] match what you meant?"
  - Q4 and S3 are RULED.
  - The section at 191-200, "Open before a tracker strangers push to", lists 9 accepted residual risks, which also need the owner's nod.
- **Guesses:** 18 in `guesses.md`, but the file **does not parse**: line 13 is blank (`./zn guesses f0428`: "0 guesses, unreadable (line 13 is not a guess: "")"; `approve --check` fails with the same message). Fixing it means editing a pushed guesses file. zz-rules SKILL.md:86 says a pushed guess is never changed, so check that `approve`, `finish` and `done` accept a removed blank line. G10-G18 concern built code; G1-G9 are mostly about unbuilt parts (scan, PR, recovery, raft branch).

### B3. Smallest honest split
- **Closes as f0428: "a host's tracker at `.tracker`: `zn init`, resolution from every folder, and the front door for the capture and read commands".**
  - Covers: S1, S3, S4, S9, S12 and S13 as built; S2, S5, S6, S8 and S10 restated as "for the commands that exist" plus the `internal/host` write path; D2-D6.
  - Proof is the Go tests in the gate.
- **New ticket, working title "A raft's code reaches the host: branch, commits, pr, scan, recovery".** Outcomes:
  - S2 for every other command, with `zn tracker worktree` and `zn tracker merge`;
  - S5-S8 and S10 as commands (`zn worktree <R>`, layers, `zn commit`);
  - S7 and S11 (`zn pr`, fork-only, a person-typed PR); S14 (OC1); D1;
  - init steps 5-7: re-pointing, adding a project to a tracker with history, scan hooks, the board path;
  - the second machine (AC9), the scan (AC8), recovery (AC10), AC4 and AC6-AC7;
  - step 8b (no links), the `<cache>/bin` shims, and the nine residual risks of 191-200.
  - Open Q1, Q5-Q8, S1 and S2 go with it.
  - It overlaps f0427's new ticket 2 (both are "a delivery in a host"). Make them one ticket or a pair, so that "host facts" and "PR state" are designed once.
- **Cannot split cleanly:**
  - S2, S4 and S12 are "every/any command" sentences. They hold for the built commands, and the remainder must carry the same sentence for the rest.
  - AC4 and AC5 are "across a fixture delivery", and no delivery exists. They must be reworded for the closable part (the six commands, fetch and worktree) and restated in the remainder.
  - `depends_on: [f0427]` stays true only for f0427's closable half (the payload). The remainder's dependencies need rewiring.

### B4. What `./zn done` refuses today, and the work to get there
- Today: no raft. `approve --check` fails on the unparseable `guesses.md`. Design is not ready. check.sh fails 9 of 10 lines. Code-review round 4 is unanswered (no refute-004). 19 findings are unharvested. There is no final review and no trace.
- Work:
  1. Owner rulings: the split, the 0.1 mode, Q2/Q3 marked ruled, and the residual risks.
  2. Fix guesses.md line 13, after checking the engine allows it.
  3. Doc rewrite: the Solution cut with `Scope decision` lines; Design condensed to the as-built text (the 114-189 rounds condensed into rules); the old init and Remotes text and the unbuilt sections moved.
  4. check.sh: AC1, AC2, AC3, AC5 and a reworded AC4, pointed at the Go tests (`go test ./internal/host -run …`, `./cmd/zn -run …`), with no Luau acceptance spec. An optional Luau spec over the binary would duplicate the Go tests (memory: fast specs).
  5. Write refute-003 and refute-004, or file them as answered from the doc's as-built rounds. Refile review-004 with step lines, or note it as invalid in harvest.md. Harvest all 19 findings.
  6. Capture the remainder ticket.
  7. A design round (cap 9).
  8. A raft, ready, a docs-only layer, the trace, a final review over about 14,400 merged lines.
  9. The owner approves 18 guesses (0.2).
  10. `done`.
- **Risk:** f0428 depends on f0427, and the engine's `ready` refuses a raft whose `depends_on` outside it is not done. f0427 must close first, or the two must close in one raft (same type: feature).

### B5. Estimate and risks
- About 300-400 doc lines condensed or moved, about 10 check.sh lines, refute files of about 40 lines, 19 harvest entries plus lessons, and 1 capture.
- Review rounds: 1-2 design rounds and 2-4 final rounds (the merged diff is large and security-heavy, and round-6 answers were never re-reviewed).
- Risks:
  - the largest unreviewed-in-tracker surface of the five;
  - review-004 was answered in the doc, not in a refute file, so a final reviewer may re-raise its findings;
  - the terminal tests have only ever run on macOS (f0428.md:187, 200);
  - the guesses file edit (2 above).

---

## C. c0436: One set of stage names (condensed from audit-C-c0436.md)
- Doc: 150 lines. Frontmatter: `design: draft`, **no `risk:` key**. check.sh has **no check lines**; there is no `acceptance/`.
- Merged slices: #721, #724, #726, #728, #731, #750 and #761 (the last is f361b504a: 92 files, +792/-248).
- Capture (82da99206): one sentence, "One set of stage names for a ticket: idea, design, code, review, approval, landed".
- **Delivered:**
  - the skill renames z-idea and z-code, with one-line aliases z-ticket and z-run, `skills.MOVED` (z-nile/engine/skills.luau:383), the lesson canon and dispatch's stored keys kept, all proven by `z-nile/tests/tooling/skill-renames.spec.luau` and the updated promoted specs (in the gate);
  - seven stage words, with bundle added by ruling, in z-nile/README.md (23, 246-259), README.html (#721-#731) and the board labels (boardview.luau:18-25);
  - the Status row label;
  - the README stage/status/folder table.
- **Partly:** stage words everywhere. Engine output still prints the old keys (dispatch.luau:88 and :479, dispatcher.luau:1507), live events and stats are not touched, and the skills do not each state the mapping.
- **Not built:**
  - "closed" shown as a word (board.html still groups under "Done");
  - every ticket at exactly one of the seven words (the run column conflates code, review and approval; Ready is an extra word, G2);
  - stored-value renames (ruling 2026-11-21: active becomes reviewing, approval becomes complete). This ruling conflicts with the Non-goal at line 33.
- **Open (148-150):**
  - (a) Non-goal against the stored-names ruling;
  - (b) keep the Ready column?;
  - (c) may the sequestered specs of c0260, c0325, c0316, c0250 and c0252 be repointed?
- **Guesses:** 3, not approved. **Reviews:** idea reviews only; no design, code or final review.
- **Split:** close the renames, the docs, the board labels and the README table. A new ticket, "Stage names in commands, board and stored values", takes engine and CLI output words, live events and stats, the shown word "closed", one word per item, the stored renames (or a re-ruling of the Non-goal), per-skill statements, and the repointing of other tickets' specs. This needs the owner's ruling on (a) first.
- **To done:**
  - write ACs with check lines naming the specs that exist (skill-renames.spec.luau and friends are already promoted tooling specs);
  - add `risk:`;
  - if it is ruled `easy` with a short note, the light path is available (zz-rules SKILL.md:84 and :185: `risk: easy`, designed, no unlanded dependency, a plain `Overrides: none`). Its current Overrides line lists already-landed promoted specs and must become `none`;
  - one final review (cap 2) acting as the design review;
  - the owner approves 3 guesses;
  - `ready <issue>`, then `done`.
- **Size:** about 200-300 lines, no engine code, 1-3 rounds.

## D. c0179: Fixture volume without fseventsd (condensed from audit-C-c0179.md)
- Doc: 289 lines. Frontmatter: `status: preparing-…`, `design: draft`, `risk: risky`, `depends_on: [c0178]`. The title and slug are still the volume's, but the H1 already says "Meter file events, and fewer files in Go tests".
- Merged: #791, 5e8f5eaa4, 35 files, +2,572/-68.
- Capture (3219117fc): one sentence, "put [fixtures] on a volume both ignore, falling back to .cache".
- **Delivered:**
  - the file-event meter: z-nile/scripts/fsevents-meter.sh and its Swift helper, proven by `z-nile/tests/tooling/fsevents-meter.spec.luau` (promoted, in the gate);
  - the AC5 baseline as a recorded number;
  - the Lune per-spec ranking handed to c0178;
  - the E8/E9 findings.
- **Partly:** fewer files in the Go tests (internal/fxtree plus templates; -64%, about 71,000-72,000 events against AC2's 60,000, which is NOT MET).
- **Not built:**
  - the volume itself, refuted by E3/E4; its detach-per-run form is now carried by c0449;
  - the other Go packages (G4);
  - the 60,000 target.
- **Stale sections:**
  - the Solution (33-38) and the "Answers to the questions" volume bullets (56-61);
  - Review status and "Next slice" (171-182);
  - the frontmatter;
  - the Test plan's case count against the log (10 vs 8; the file has 10);
  - spend.md rows for design rounds 002-007, whose files are gone.
- **check.sh:** all five ACs have lines and every path exists, but the lines are macOS-only. AC2 fails (60,000) and AC5 fails unless `C0179_AC5=1`.
- **Reviews:** `design-review-001.md` is a lead's transcription that `rounds` cannot parse. There is no refute, no code review and no final review.
- **Guesses:** 8, not approved.
- **Open:** AC2's number; volume or not; fswatch or Swift.
- **Split:**
  - Close c0179 as the meter plus the Go templates, retitled, with AC2 reworded to the measured number if the owner accepts it.
  - The volume goes to c0449, by the owner's ruling. It cannot split cleanly, because the one Decided line (27, "Yes, and fewer files") spans both the volume and c0178.
  - A new ticket, "Go test fixtures: the rest of the events", is needed only if the owner keeps 60,000: the target, the other packages and a `--by-folder` spec.
- **To done:** the full path (risky). A design round in parseable form, a raft, a final review over 2,572 lines, 8 guesses approved, and a Mac run of the long check.sh.
- **Size:** about 150-250 doc lines, 1-2 design rounds plus 1-3 final rounds.

---

## E. d0426: Spec runs leak kernel memory (brief)
- Doc: 131 lines. Frontmatter: `design: draft`, **no `risk:` key** (rounds cap 5 = the normal default), `status: new`.
- Merged:
  - #713 329b1403b: z-nile/lib/kzone.sh, called in z-nile/check.sh:39-43 (not for `--plan`), `z-nile/tests/tooling/kzone.spec.luau`, a zz-test note (SKILL.md:104) and the lesson zz-test/gate-runs-leak-kernel-memory.
  - #745 ce865f630: z-nile/lib/gatequeue.pl and gatequeue.sh, `./zn gate-queue` (main.luau:73, 3487), exit 75 through sh.luau, ac.sh and watchcmd.luau, tests/run.luau queueing, `gatequeue.spec.luau` and `gatequeue-net.spec.luau`.
  - #762 (lesson source fix).
- All three specs are promoted tooling specs, in the gate.

### E1. Captured outcomes

The capture (f76cf6eae) carries the full Problem and Solution. There are no Decided or Scope lines.

| Solution bullet (line) | state | proof |
|---|---|---|
| the gate **and the spec runner** read `data.kalloc.1024` before starting, warn and refuse (35) | **partly**: the gate only (check.sh:39-43); tests/run.luau never reads it (`grep kzone z-nile/tests/run.luau`: none; #713's second commit "the outermost gate alone runs it") | kzone.spec.luau (gate) |
| prints nothing where it cannot be read (36) | **delivered** (kzone.sh:17-18) | kzone.spec |
| warning and refuse levels are settings, below 20,764,352 (37) | **delivered** (`ZN_KZONE_WARN` 5,000,000, `ZN_KZONE_REFUSE` 10,000,000, kzone.sh:19-22) | kzone.spec |
| one command prints the count and both levels; the stop message and the board show them (38) | **not built** (`gate-queue` shows holders, not the count; no stop-message or board change) | none |
| name the leaking operation, with bisection readings (39) | not built | none |
| remove the leak (40) | not built | none |
| leak check: 3 gates, 5 min, at most 1,000 elements, printed, passing on the owner's machine (41-43) | not built | none |
| from the first merge, zz-test, **zz-execute and zz-review** say "targeted specs while iterating, one gate at a time" (44) | **partly**: zz-test SKILL.md:104 and the lesson only; `grep` finds nothing in zz-execute or zz-review | none (prose) |
| the change that passes the leak check removes that guidance (45) | not built (it waits on the fix) | none |
| (not captured) the machine-wide gate queue, exit 75 (Design "Step 2", 48-57) | **delivered**: the lead's addition, recorded as G5 ("the queue … is the lead's addition to the captured Solution") | gatequeue.spec and gatequeue-net.spec (gate) |

Count: delivered 2 (plus the uncaptured queue); partly 2; not built 7.

### E2. Design versus what was built
- **Design** documents only Step 2 (the queue). There is no Step 1 (the zone guard) and no plan for the bisection or fix. Scalability, Maintainability, Usability, Affected specs, Unknowns and Regression guard are empty, and Overrides is the template placeholder (line 82: `<promoted specs … or none>`).
- **ACs:** AC1-AC4 all cover the queue, and check.sh:14-17 runs existing specs. No AC covers the zone guard or any captured outcome. Rules and mutants are all queue rows marked "run".
- **Reviews:** none (`rounds`: "no review yet … at most 5" for design, code and final). **Open to the human:** "none". **Guesses:** 6 (G1-G6, build step), not approved.

### E3. Split
- **Close as d0426, retitled for example "The gate reads the leaking kernel zone and runs one at a time":** the guard and the queue.
  - Needs the owner's scope decision, because the captured defect (the leak) is not fixed, and G5 asks him to accept the queue as the means.
  - The Design needs a Step 1 section for the guard and an AC for it (kzone.spec exists).
- **New defect ticket, working title "Find and remove the kernel-zone leak":**
  - the spec runner's own read;
  - the meter command, the stop message and the board;
  - the bisection, the fix and the leak check;
  - guidance in zz-execute and zz-review, and its removal.
- **Cannot split cleanly:** the guidance bullets (44-45) are tied to the fix. "From the first merge" belongs to the closable part, and "removed when the fix passes" belongs to the remainder. The closable part must add the missing zz-execute and zz-review lines, or the owner must rule them out.

### E4. To done
- `approve --check`: "d0426 has no approval".
- Work:
  - doc: add the Step 1 design for the guard, fill Overrides (likely `none`; verify with `lune run z-nile/affected` over the Touched paths), add an AC for the guard, and cut the Solution with a Scope decision;
  - add `risk:`. It touches the gate and the guards, so a light path is unlikely: zz-review Final mode says a guard or the gate is not easy;
  - a design round, a raft, a final review over about 1,100 merged lines, 6 guesses approved, and `done`.
- **Size:** about 80-120 doc lines, plus 2-5 lines of skill text if the zz-execute and zz-review guidance is added. 1-2 design rounds and 1-2 final rounds.
- **Risk:** the owner's memory "gate runs leak kernel memory" says the leak is live. Closing the defect's ticket without the fix must not read as "fixed".

---

## Summary

| ticket | closable now? | outcomes delivered / partly / not | remainder ticket | blockers | size of closing |
|---|---|---|---|---|---|
| f0427 | no | 4 / 3 / 10 | "zn installs and upgrades itself" (release, install, version and upgrade lifecycle, Linux proof AC2) + "zn delivers a raft in a host repository" (S3-S13, S15, AC4-AC15) | no closing mode for merged code (0.1); 12 of 15 check lines name missing specs, AC2 is `exit 1`; design review unparseable, no code or final review filed; 14 unapproved guesses mostly about unbuilt parts; G7 contradicts the code | about 300 doc lines moved, 2 captures, 1-2 design + 1-3 final rounds over about 4,400 merged lines |
| f0428 | no | 9 / 7 / 4 | "A raft's code reaches the host: branch, commits, pr, scan, recovery" (merge with f0427's host-delivery remainder) | no acceptance/ folder, 9 of 10 check lines name missing specs; guesses.md unparseable (line 13); review-004 unanswered, has no step lines; 19 findings unharvested; depends on f0427 | about 350 doc lines condensed, refutes, 19 harvest entries, 1 capture, 1-2 design + 2-4 final rounds over about 14,400 lines |
| c0436 | no (closest after d0426) | about 5 / 3 / 4 | "Stage names in commands, board and stored values" | owner ruling (a), Non-goal vs stored names; no ACs or check lines; no `risk:`; 3 guesses; no reviews | about 250 lines, light path possible if ruled easy: 1-3 rounds |
| c0179 | no | 4 / 1 / 3 | volume to c0449 (by ruling); "Go test fixtures: the rest of the events" only if 60,000 is kept | AC2 fails at 60,000; 3 Open items; 8 guesses; design review unparseable; risky, so the full path; macOS-only check.sh | about 200 doc lines, 1-2 design + 1-3 final rounds |
| d0426 | no (smallest) | 2 (+ queue) / 2 / 7 | "Find and remove the kernel-zone leak" (runner read, meter command, stop message and board, bisection, fix, leak check, guidance) | the captured leak is unfixed (scope ruling); no design for the guard, Overrides placeholder; no reviews; 6 guesses; no `risk:` | about 100 doc lines, 1-2 design + 1-2 final rounds over about 1,100 lines |
