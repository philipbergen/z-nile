#!/usr/bin/env python3
"""d0331: the four skill edits of the Design, applied to a clone. Usage: apply-docs.py <clone>
The step-3 anchor carries d0333's "(steps 1 and 2)" (2026-11-15); the edit drops it (Guess (prep) G1)."""
import sys

root = sys.argv[1]

def sub(path, old, new):
    p = f"{root}/{path}"
    s = open(p).read()
    if s.count(old) != 1:
        sys.exit(f"{path}: anchor found {s.count(old)} times: {old[:60]}")
    open(p, "w").write(s.replace(old, new))

sub(
    "z-nile/skills/zz-execute/SKILL.md",
    "2. If `main` moved, `./zn restack <R-id>` (renumber colliding IDs, rerun `z-nile/check.sh --affected`, commit with `./zn commit --phase deliver`), so the stack is on that main before `done`.",
    "2. A `main` that moved needs no restack: `./zn finish`, `./zn trace` and `done` judge layer 1 against the commit where it left `main`, and `done` merges the stack onto the newest `main` and runs the gate on that merged tree. If `main` moves again during that gate, `done` merges and gates again by itself, up to nine times. Run `./zn restack <R-id>` only when `done` reports a conflict or a red gate on the merged tree (renumber colliding IDs, rerun `z-nile/check.sh --affected`, commit with `./zn commit --phase deliver`), after a fix on a lower layer, or when `./zn trace` or `done` asks for it on a raft readied `--on` another raft once that raft has landed.",
)
sub(
    "z-nile/skills/zz-execute/SKILL.md",
    "after the last layer is finished and restacked (steps 1 and 2), print the trace skeleton",
    "after the last layer is finished, and the layers above any fixed layer are restacked, print the trace skeleton",
)
sub(
    "z-nile/skills/zz-rules/SKILL.md",
    "`./zn restack <R-id>` rebases the layers above a change.",
    "`./zn restack <R-id>` rebases the layers above a change. Layer 1 only has to sit on a commit of `main`: `main` moving past it is no reason to restack, and `./zn done` merges the stack onto the newest `main` itself.",
)
sub(
    "z-nile/skills/zz-review/SKILL.md",
    "Run once per raft on the finished, restacked stack, on the review model",
    "Run once per raft on the finished stack, with the layers above any fixed layer restacked, on the review model",
)
