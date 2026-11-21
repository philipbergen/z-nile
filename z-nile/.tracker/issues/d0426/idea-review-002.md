# Idea review 002

## Findings

- F1: The Solution assumes the leak is in the spec runner, but nothing in the Problem shows that. The only measurement in the Problem is of a whole `z-nile/check.sh --affected` run. That run also does format, lint, type checks, Rojo builds and the Go build, vet and test stages added in f0424. The Problem also says "the operation that leaks is not named." So "the ticket records which spec-runner operation leaks" and "the spec runner is changed so it no longer performs that operation" can turn out impossible to meet: the bisection might find the leak in a gate stage, or in a spec's own fixture code. That would happen even though the work found and removed the leak. Non-goal 1's "stops the spec runs from triggering it" makes the same assumption. There are two fixes. One is to add the evidence that points at specs to the Problem: the earlier readings found that fixture-heavy spec files add hundreds of elements each and a spec without fixtures adds none. The other is to say "gate operation" in those sentences and let the bisection decide where the fix goes.

## Verdict

revise
