# Review 008: R0002 (design mode)
Inputs: prep-inside-repo at b24e96f; `git diff 23c3d71 HEAD` and `git diff b4b62b7 HEAD`. Files: `tracker/rafts/R0002/{R0002-worktrees-by-default.md,check.sh,design-review-007.md,design-refute-007.md}`, `tracker/issues/c0046/{c0046-inside-repo-worktrees.md,check.sh,acceptance/launch.spec.luau}`, `tracker/issues/c0005/{c0005-worktrees-by-default.md,check.sh,acceptance/worktree.spec.luau}`, `tracker/issues/c0045/{c0045-parallel-workstreams.md,check.sh,acceptance/workstreams.spec.luau}`, `tracker/issues/c0044/{c0044-doc-filename-without-slug.md,check.sh}`, `scripts/tracker.sh`, `scripts/check.sh`, `scripts/lib/graph.luau`, `.luaurc`. Ran, all in the scratchpad and outside the repo: c0046's `launch` block pasted into a copy of `scripts/tracker.sh`, under macOS `/bin/bash` 3.2.57 with the wrapper's `set -euo pipefail`, and a fake `lune` that prints a path, nothing, an extra line or fails. Tested with empty or missing arguments, `--` edge cases, an option-like target, arguments with spaces, an empty string, `*`, quotes, a newline and a second `--`, and exit 200. Tested a relative command, a builtin (`cd`), an exported function and a non-executable file on `PATH`. Ran it under a pty (`script -q /dev/null`) with a real `^C` byte sent to a child that traps INT. Checked which `CLAUDE.md` a headless `claude` loads in a nested worktree of a scratch repo, and whether an ancestor `.luaurc` reaches `luau-lsp analyze` and `lune run` in a nested directory. Also ran `scripts/tracker.sh promote-check R0002` (OK, 9 passed) and `bash -n` / `/bin/bash -n` on all five `check.sh` files (clean). Computed `workstreams R0002` by hand from c0045's algorithm, the current `depends_on` and the four Touched-modules lists: `c0044 wave 1`, `c0005 wave 2 after c0044 (depends_on)`, `c0046 wave 3 after c0005 (depends_on), c0044 (overlap)`, `c0045 wave 4 after c0005 (depends_on), c0044 (depends_on), c0046 (depends_on)`, `parallel: no`. RC1's four regexes match.
Dropped from design-review-007: F1, F2, F3, F4, F5, F6, F7. Each one is fixed in the documents, specs and `check.sh` files as the refutation says.
- F1: `launch` is a bash `exec`. Under a pty the command had a tty on fd 0 and received the `^C` itself (it trapped INT and ran to its end). Its exit status 5 reached the caller, and its parent was the caller's shell: the wrapper was replaced. `set -u` with an empty `"$@"` is fine on 3.2. Exit 200 propagates.
- F2: the spec has three strays and a count.
- F3: AC6 greps c0005's markers.
- F4: no `../pickman` in the prescribed text.
- F5: every awkward argument, and also a newline, arrives intact.
- F6: my own nested-worktree run loaded only the inner `CLAUDE.md` (`MARK-INNER`, not `MARK-OUTER`).
- F7: all its bullets are fixed; c0005 has the detached-prune case and a P3 row.
Leftover sweep: nothing outside history and the fixtures' branch names (`R0001-demo` as a branch is correct) still says `.worktrees`, `ensureWorktree`, `cmd.launch` or `<R-id>-<slug>` as a directory. No forbidden phrase in one member's AC grep (c0005 AC5, c0044 AC9, c0046 AC6, c0045 AC6) is required text in another's.

### F1 [medium] `launch` as written doesn't stop on a bad path from the worktree step. With empty output it runs the agent in the main checkout (`cd ""` succeeds). With extra output it falls through to `exec lune … "$@"` and runs the agent's arguments as a tracker command
Where: c0046 Design, `scripts/tracker.sh: launch` block (`path=$(lune run … worktree "$target") || exit 1` … `cd "$path" && exec "$cmd" "$@"`); Rules and mutants (no row); Verification log (the "`; exit 0` is equivalent" note)
Evidence: the block runs under macOS `/bin/bash` 3.2 with `set -euo pipefail`, and a fake `lune` stands in for the worktree step.
- The worktree step exits 0 and prints nothing. The wrapper prints `launching rec in ` and runs the command with `pwd=<repo root>`, the main checkout. That's because `cd ""` returns 0, which c0005's E5 already records and designs its hooks around.
- The worktree step prints one extra line (`warning: something`, then the path). The wrapper prints `cd: warning: something\n<path>: No such file or directory`. Under `set -e`, a failing command that isn't the last one in an `&&` list doesn't exit the shell, so the `if` block ends and the wrapper's last line runs: `exec lune run scripts/tracker/main -- "$@"`, where `"$@"` is now the command's own arguments. The fake `lune` received `args=[a]` and exited 9. So `launch R0002 -- claude done R0002` would run `tracker.sh done R0002`.
- The Verification log explains away the `; exit 0` mutant because "under `set -e` a failing last command of an `&&` list already exits". That holds for `exec` but not for `cd`, and `cd` is the failing command here.

Today's `worktree` passes c0005's stdout-equality assertions in the cases the spec covers. But nothing guards the untested branches: an origin-only resume that streams git's output, c0045's `--from`, or a tool shim printing to stdout on a fresh machine. And the failure mode is exactly what c0046 exists to prevent.
Critique: a two-line fix. The tempting version is only `cd "$path" || exit 1`, which still accepts an empty path.
Consequences:
- Validating the path adds one rule: the worktree step must print exactly one absolute directory path.
- Moving `command -v` after the `cd` makes a relative command resolve against the worktree, the directory `exec` uses. Today it resolves against the repo root, because the wrapper `cd`s there first (see F5).
- The spec can't make the real `worktree` misbehave, and a fake `lune` on `PATH` is shadowed, because the wrapper prepends `$HOME/.rokit/bin`. A case therefore has to set `HOME` to a scratch directory whose `.rokit/bin/lune` is a fake. Git in the fixture only needs the per-repo identity the spec already sets.

Recommendation: replace the tail of the block with
```bash
path=$(lune run scripts/tracker/main -- worktree "$target") || exit 1
if [[ $path != /* || $path == *$'\n'* || ! -d $path ]]; then echo "launch: the worktree step printed no usable path" >&2; exit 1; fi
cd "$path" || exit 1
cmd=${1-claude}; if [[ $# -gt 0 ]]; then shift; fi
p=$(type -P -- "$cmd" || true); [[ -n $p && -x $p ]] || { echo "cannot run $cmd: not found" >&2; exit 1; }
echo "launching $cmd in $path" >&2
exec "$cmd" "$@"
```
Both the `$'\n'` pattern and `type -P` work on bash 3.2 (checked). Then:
- Add the Rules row "a worktree step that prints no usable path launches nothing". Its mutants are the Design's own `cd "$path" && exec` (runs in the main checkout, or falls through to `lune`) and `cd "$path" || exit 1` without the path test.
- Add a spec case that sets `HOME={base}/fakehome` with a fake `.rokit/bin/lune` printing nothing, then two lines. Assert that the launch fails, that the fake agent's log isn't written, and that no tracker command ran.
- Correct the `; exit 0` note in the Verification log.

### F2 [medium] c0046's AC5 case fails a correct c0005 prune that writes its `kept <path> (named worktree…)` line to stderr, a stream c0005 never fixes
Where: `launch.spec.luau:236` (`t.expect(has(r.stderr, `{main}/.worktree/`)).toBe(false)`); c0005 Design, `worktree-prune` steps 5 and 6 (the "listed as `kept …`" and "print one line per removed worktree" lines name no stream); c0005 spec line 386 (`r.stdout .. r.stderr` contains `capture-demo`, so either stream passes)
Evidence: when c0046's prune case runs, `{main}/.worktree/capture-demo` exists (a named worktree created by the launch cases), so prune prints `kept {main}/.worktree/capture-demo (named worktree: …)`. c0005's design and spec both allow that on stderr, which is a natural choice for a diagnostic. c0046's assertion then finds `{main}/.worktree/` in stderr and fails AC5, even though no warning names it. The prototype passed only because it happened to print the kept line on stdout. An executor who chooses stderr in c0005 finds out at c0046, and then has to change already-committed c0005 behaviour or escalate over a sequestered spec.
Critique: an implicit cross-member contract. The tempting fix is to add "kept lines go to stdout" to c0005's Design alone. That works, but the assertion still tests more than AC5 says ("doesn't warn about worktrees inside").
Consequences: narrowing the assertion to warning lines keeps every mutant the row lists killed. "Warn about everything" still gives 5 warnings, not 3, and "prefix without the slash" still leaves `.worktree-old/y` unwarned. Stating the stream in c0005 keeps the two specs from drifting.
Recommendation:
- Change line 236 to `t.expect(has(r.stderr, `warning: {main}/.worktree/`)).toBe(false)`.
- In c0005 steps 5 and 6, say that removed and kept lines go to stdout and that stderr carries only failures and the stray warnings.

### F3 [medium] A worktree nested in the repo inherits the main checkout's `.luaurc`. `luau-lsp` and Lune both merge ancestor configs, so the gate in `.worktree/<id>` isn't hermetic, and E2 only tested the other direction
Where: c0046 E2 ("no tool scanned the nested copy"); R0002 Risks; `scripts/check.sh:40,48` and `scripts/tracker/main.luau:387` (`luau-lsp analyze --base-luaurc=.luaurc …`); `.luaurc` (relative aliases `./src/shared/Logic` and the like)
Evidence: in the scratchpad I made an outer directory whose `.luaurc` defines `outeronly: ./o`, and an inner directory whose own `.luaurc` doesn't define it but has a file that runs `require("@outeronly/m")`.
- From the inner directory, `luau-lsp analyze --base-luaurc=.luaurc --platform=standard t` logs `Loading Luau configuration from <outer>/.luaurc`, then `<inner>/.luaurc`, and passes. `lune run t/a.luau` prints `1`.
- With the outer `.luaurc` removed, luau-lsp reports `TypeError: Unknown require`.
- Running `promote-check R0002` in this very worktree logs `Loading Luau configuration from /Users/philipbergen/code/pickman/.luaurc` before the worktree's own file.

So in `.worktree/<id>`, an alias that the branch renames or removes still resolves, and it resolves to the main checkout's files. The gate passes locally and CI (a clean clone) fails. Worse, a stale require runs tests against `main`'s code instead of the branch's. The sibling layout didn't have this.
Critique: this is a cost of the user's inside-the-repo rule, not a reason to reverse it. But the design says the nested layout has no such effect. The tempting fix is a sentence saying "CI catches it". That's true, but only after a push, and the local gate result then disagrees with CI with no explanation.
Consequences:
- Rafts that touch `.luaurc` aliases (rare, but an architecture change can) need a hermetic check.
- `graph.luau` reads only the local `.luaurc`, so the dependency-graph stage may already reject an undefined alias under `src` and `tests`. That's unverified, and it doesn't cover `scripts`.
- Any fix inside `check.sh` has to work in both layouts: the main checkout, and a nested worktree.

Recommendation:
- Record this as a new c0046 experiment (E5, PASS: an ancestor `.luaurc` is merged by luau-lsp 1.x and Lune 0.10.5) and add a line to R0002's Risks.
- In the tracker skill's Worktrees section, add one sentence: "a change to `.luaurc` aliases is verified in CI or in a clone outside the repo, because a nested worktree also sees the main checkout's `.luaurc`".
- Optionally run a cheap prep experiment to check whether the `graph` stage of `scripts/check.sh` already fails on an alias that is missing from the local `.luaurc`. If it does, say so. If it doesn't, file the gate guard as a follow-up. Don't widen this raft (ask the user).

### F4 [medium] c0046 has humans run `scripts/tracker.sh launch` from the main checkout, but never adds it to c0005's rule-1 whitelist, so c0005's JC1 fails on the raft's end state
Where: c0005 Design rule 1 (the "complete list of commands that may run" in the main checkout: `worktree` and `worktree-prune`, and c0045 adds `workstreams`); c0005 JC1 ("Fail: any main-checkout command that isn't on the whitelist"); c0046 Docs (make-prompt report, SETUP.md and AGENTS.md launch line, tracker skill), which never says `launch` joins the whitelist, while c0045 says exactly that for `workstreams`
Evidence: the make-prompt report ends with `scripts/tracker.sh launch R…`, run by the human in the main checkout (that is the only place `launch` is useful). Rule 1 as c0005 writes it doesn't list `launch`. A Phase 4 reviewer ruling on c0005's JC1 over the final skills must quote it as a failure. Or the executor adds it on their own, an undocumented deviation.
Critique: a coherence gap between members. It's small, but JC1 is a ruling the raft can't pass without it.
Consequences: `launch` only ensures a worktree, which is already whitelisted, and then `exec`s in it, so whitelisting it changes nothing about what the main checkout is allowed to mutate. Agents don't use `launch` (they `cd` with `worktree`), so `.claude/settings.json` needs no new permission. Saying so avoids a follow-up finding.
Recommendation:
- In c0046's tracker-skill bullet, add "`launch` joins the rule-1 list of commands that may run in the main checkout (it only ensures the worktree and replaces itself with the command there)".
- Add `launch` to c0046's JC1 pass text.
- Optionally extend AC6 with `grep -qF "launch" ` on the rule-1 paragraph. If that's hard to anchor, leave it to JC1.

### F5 [low] Loose ends
Where: c0046 Design `launch` block and its bullets; Rules and mutants; Verification log; R0002 Experiments phase and RC1
Evidence and Recommendation, item by item:
- **Relative commands and non-executables**: `command -v` runs before the `cd`, in the repo root, because the wrapper `cd`s there first. So `launch R2 -- ./localtool` with the tool in the repo root passes the check, and then `exec` fails with bash's own `…/.worktree/R2/localtool: No such file or directory`. A path relative to the user's own directory is never found. A non-executable file on `PATH` passes `command -v` on 3.2 and fails with bash's `Permission denied`. AC3's "a command that can't start is `cannot run <command>`" doesn't hold for either. F1's `type -P` plus `-x` after the `cd` fixes both. Document that a relative command is resolved in the worktree.
- **An empty command becomes `claude`**: `launch R1 -- "" foo` ran `claude foo`, because of `${1:-claude}`. F1's `${1-claude}` makes it `cannot run : not found` instead.
- **A typo'd command still creates the worktree**: the command check comes after the worktree step. That's harmless (idempotent), but say so, or accept it knowingly.
- **The row "the launcher is replaced by the command" can be `run`, not `reasoned`**: the fake agent can record `ps -o comm= -p $PPID`. With `exec` its parent is the spec's `lune` process; without `exec` it is `bash`. That gives a checked proxy for the part OC1 now carries. My pty run confirms the design's claims: a tty on fd 0, INT delivered to the command, its status propagated.
- **Row 3's "no default" mutant** isn't among the eleven planted mistakes in the Verification log. Run it or mark it `reasoned`.
- **Stale wording**:
  - c0046 Maintainability says "One function creates worktrees, for `worktree` and `launch`". It is one command now.
  - R0002's Experiments phase says "with all three prototypes", and its RC1 exit criterion says "ties the three issues together". There are four.
  - c0044 still says `design: ready` while its siblings say `reviewed`. Harmonize when the round closes.

Verdict: changes
