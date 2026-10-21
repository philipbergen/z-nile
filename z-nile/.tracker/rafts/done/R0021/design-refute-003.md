# Answers to design review 003 (R0021, formerly R0019)

- F1: fixed:
  - **Specs mode**: `pre-push` now allows a push only into an existing local repository that isn't protected, so every non-local form is refused: https, ssh, `host:path`, ssh aliases.
  - **No credentials**: specs mode resets git's credential helper list (an injected empty `credential.helper`; verified with `GIT_TRACE` that the keychain is never asked), unsets `SSH_AUTH_SOCK`, sets `GIT_TERMINAL_PROMPT=0`, and makes `GIT_SSH_COMMAND` refuse (verified for both `ssh://` and `user@host:` forms).
  - **Cases**: `fence :: specs get no GitHub credentials and can't push to any network remote` (https, scp-form, alias, the helper list, ssh) and `repo-fence :: specs have no GitHub credentials and push only into fixtures`.
  - **Mutants**: N3 (non-local forms allowed), N4 (helper kept) and N5 (ssh allowed) are each killed.
- F2: fixed: under an outer sandbox the gate's jail case no longer fails on the label. It probes the same writes and passes only if they are refused; otherwise it names the writable paths and says to run the gate outside a permissive sandbox. The testing skill, AGENTS.md and R0021's Risks now describe exactly that.
- F3: fixed: the jail case probes the main checkout when run from a worktree. Mutant J4 (that rule removed) is killed. `~/.gitconfig` and `~/.config/git` are now denied too (from F6), with probes: append-nothing on `~/.gitconfig`, a probe file in `~/.config/git`. J6 is killed.
- F4: fixed: the identity refusal shows the value and its origin (`git config --show-origin`) and says "Stop and report this; do not repair the repository yourself", matching the stop rule. It no longer suggests a command.
- F5: fixed: `origin/main` (`9fa1499`) is merged into prep and into the prototype. The raft is renumbered R0019 → R0021 with `tracker.sh renumber`, after aborting the add/add merge as the Conflicts rule says. c0058 was free and keeps its number. Re-measured: full gate jailed, 751 passed, 0 failed, 119 files, 20.5 s; c0058 AC1-AC9 and RC1 pass.
- F6: fixed or answered, point by point:
  - **Case-sensitive scan**: the scan lower-cases both sides (`core.hookspath` is caught; S5 killed).
  - **Fetch in specs mode**: the fetch exception now applies only outside spec runs (`PICKMAN_FENCE_SPECS` unset). The fetch case checks both sides, and a `check.sh` started inside a spec run keeps the spec's limits (R4 killed).
  - **The jail only covered the starting repository**: it now also denies every repository in `PICKMAN_FENCE_REAL_GIT` and its main checkout. New AC9 (a `check.sh`-level check, since specs are already jailed) runs a copy's spec that tries to write the real checkout. J5 survived every spec case and is killed by AC9.
  - **`~/.gitconfig`**: denied, see F3.
  - **Rollout**: R0021's Order section now says that open worktrees run unguarded until they merge `main`, and that the landing report tells every session to merge first.
  - **The rule "check the fixture before each write"**: it now applies to new and edited specs. Older ones rely on the jail; retrofitting them is a follow-up, to file at the user's go-ahead.
  - **Scan scope**: merging `main` brought in other rafts' prepared acceptance specs (R0020/c0053 and R0019/c0052) that name guard variables, override `GIT_CONFIG_COUNT`, or use a non-fixture identity. The scan now covers what runs as a check (`tests/`, `scripts/` and every `check.sh`), and prepared specs are scanned once promoted. Those two preps are flagged in c0058's Regression guard and R0021's Order section, to be adapted at the user's decision.
