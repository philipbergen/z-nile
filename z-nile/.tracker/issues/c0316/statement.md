# c0316: the agreed statement

The wording the user and the capturing session agreed on 2026-11-13, kept word for word because the idea stage's outcomes name "the three ordered goals" without quoting them (Problem, Scope decision).

## The user's request (verbatim, 2026-11-13)
"The primary goal of this system is that we catch every mistakes in review,
before it merges, both in ideas, designs, and implementation, that in effect every change we make is the intended
change without rework, regression, or unintended consequence. The secondary objective is that humans review ideas and
designs and that the agents carry out code implementation, verification and merge without human intervention. The
tertiary objective is to do this cost efficiently, ie both in tokens and in wall clock time, so every time something
goes to the next stage in the pipeline with a mistake from a previous step, that's a sign of underspecification or bad
design and there's a lesson to be learned, so we take that lesson to heart and store it to memory."

## The statement (version 2, with the user's seven rulings of 2026-11-13)

**z-nile's goals, in order. When two conflict, the earlier one wins.**

1. **Every change is the intended change.** Every mistake is caught in review before it merges: in the idea, in the
   design and in the implementation. Nothing merges that needs rework, causes a regression or has a consequence
   nobody intended. *Target: no escape after a merge (no defect issue, no revert).*
2. **Humans review ideas and designs; agents do the rest.** Once a design is approved, agents implement, verify and
   merge without a human. A human is asked again only for what the approved idea and design did not decide.
3. **It costs as little as it can,** in tokens and in wall-clock time, without giving up goal 1 or 2.

**Only the human shortens a check.** An agent never skips or shortens a check that a design or a skill requires. If
its cost looks too high, the agent stops and asks, and that question is an escape (the check was designed too
expensive).

**An escape** is a mistake found at a later stage than the one that made it. The stages are idea, design,
implementation, merge, and after the merge. Each of these is an escape:
- a review finding against an earlier stage's work (a design review that finds a hole in the idea; a code review
  that finds a hole in the design);
- a question to a human during implementation, verification or merge;
- a question to a human during design that the idea could have settled. A question only the design work could
  surface is not one; the agent records which it is, with its reason;
- rework: a stopped build, a redesign after approval, a defect issue, a reverted merge;
- a design or spec made stale by a moved `main`, when work was lost (a build already started). Rebasing a design
  before its build starts is upkeep, not an escape.

**Every escape leaves a lesson.** An escape means an earlier stage was underspecified or badly designed. Its harvest
entry names the stage that should have caught it and a lesson (new, or a new source for an existing one), or
`one-off: <reason>`. Lessons live in the lessons folder of that stage's skill, which is the system's memory and is
read by every CLI. **Work with an escape that has no harvest entry cannot land**; the tracker refuses it, as it
refuses an unharvested review finding today.

**The stage's reviewer checks the judgement.** Every "not avoidable" verdict on a design question and every
`one-off` is challenged by the adversarial reviewer of that stage as part of its review.

**Measure.** Escapes after a merge: target zero. Escapes between earlier stages: counted per stage, each with its
lesson, no numeric target; the count should fall. The 20% rework figure stays in the report as history.

## The user's seven rulings (2026-11-13), each a decision line
- A human question during design is an escape "only if avoidable": when the idea could have settled it.
- Goal 1 against goal 3: "Only the human" shortens a verification step.
- The lesson rule: "Blocks the landing".
- A design made stale by a moved main: an escape "only if work was lost".
- Who checks "not avoidable" and "one-off": "The stage's reviewer".
- The target: "Zero past merge, count the rest".
- c0256's 30 dispatcher mutants not rerun on 2026-11-12: "Leave to the raft".

## First lesson to record with it
An agent that asked the human does not go on with its own recommendation when the answer decides whether a required check runs. What happened: on 2026-11-12 the lead of c0256's prep skipped 30 of 63 dispatcher mutants on its own recommendation, with no answer, to save CPU. Check: did a human say this check may be shortened?

