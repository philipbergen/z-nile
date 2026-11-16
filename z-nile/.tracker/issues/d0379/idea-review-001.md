# Idea review 001

## Findings

- F1: The non-goal "does not change … what a worker with no raft named does after a raft lands" can't hold alongside Solution bullet 1. Both kinds of worker get the `end` line from the same string, in `work.forRaft` at `z-nile/engine/work.luau:208`. z-work step 1 has a worker that was given no raft pass the raft's id on every later call while it carries one, so `./zn work next <R>` prints it the same `<R> landed. Stop.` line. If that line now says to finish Phase 6 first, the worker with no raft named is told to do something new after a landing. That worker also has the same defect: the no-raft branch of step 6 ("say one line … then run `./zn work next` with no raft") never mentions Phase 6 either. So the non-goal either contradicts the Solution, or it fences out the same gap on the second path. If it is the second, it narrows the captured scope, and only the user can make that cut.

## Verdict

revise
