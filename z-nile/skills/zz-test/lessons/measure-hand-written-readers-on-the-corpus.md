---
title: A hand-written reader of shell is measured against the corpus, not proved by review rounds
when: both
tags: [scanners, shell, corpus, mutation]
check: Is there a repeatable experiment that runs the new reader and the one it replaces over every real file (live and finished) and lists what it loses and gains, and does the design list the forms it does not model as known edges instead of claiming the reader fails closed?
---
A reader of shell text (the check-paths scan) models some forms and fails open on the rest. Each review round finds a construct it does not model (comments, line-end parentheses, heredocs, scopes, a second tokenizer); more rounds find more, and a claim that the reader "fails closed" is false the first time a quote or scope is misread.

**Why:** c0371 design reviews 001 to 003 found structural highs in the reader every round (cross-line state, comments, `)` at a line end, quote contexts, heredocs and `$'…'`, bash scopes for `cd`, separate tokenizers). The user ruled "land with known edges".

**How to apply:** keep an experiment in the issue's `experiments/` that builds the old reader from `origin/main`, runs both over every check.sh in the checkout and prints the literals lost and gained and which would be reports (E8); fix every regression against the old reader with a case and a mutant; list each unmodelled form as a known edge; do not write "fails closed" for a reader that reads text with heuristics.

Run the old reader beside the new one on every corpus the design cites, the open worktrees included (c0371 design review 004 F2: the first experiment compared the checkout only, and c0261's `git grep` line, open in 48 worktrees, was a regression it did not see).

The corpus shows only the shapes that exist today: R0112 code review 001 found four more unmodelled shapes by reading the module (a root cd inside a heredoc body, `$(( 1 << 2 ))` taken for a heredoc, a quoted lone `{` pushed as a brace group, `grep -q "^$f$"` counted as a use), none in the 671 files E8 read. They go to the Known edges or to a follow-up with a case each (c0381), and the experiment stays the regression measure, not the proof.

R0112 final review 001 F4 is one more of the same kind: a use of the loop variable found by a prefix match (`$fx`) or inside a comment. A reader's "does the body use the variable" test is a word test in the body's own context, and needs a case for a longer name and for a comment (c0382).

**Note** (f0421 design review 001 F8, 2026-11-24): `identity` and `spell` split model ids into family and effort, and AC31 tested only the ids someone picked. The real listings carry four more axes (fast, thinking, a variant word, spelling per family): `claude-opus-5-5-thinking` was read as another model, and `grok-4.7-build-fast` started `--model grok-4.7-build`. Check: has the reader been run over every id of the saved CLI listings, with the list of known edges pinned?
