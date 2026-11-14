---
title: A rule the tooling enforces on a step's behaviour is written in the skill that step reads, with the way on for what it forbids
when: design
tags: [dispatch, skills, rules]
check: For each rule the design makes the dispatcher (or any tool) enforce on what a step may do, which sentence of the skill that step reads states it? Followed literally, does that skill ever break the rule, and what does it tell the step to do in the case the rule forbids?
---
A rule enforced only in code is learned by the step when it fails, and the failure message is printed to the user, not to the step.

**Why:** c0256 design review 007 F1: the dispatcher failed a z-ticket that made its issue and then asked ("a capture asks before it makes") and dropped the user's answer, while z-ticket's own skill pushed the stub at step 2 and could find something to ask at steps 4 and 5. Six earlier review rounds and a build had accepted the rule without asking where z-ticket would read it.

**How to apply:** put the rule in the step's skill at the step it constrains, name the path for the forbidden case (here `## Open to the human` in the issue, which the chain already stops on), restate it where the mechanism is documented, and pin both sentences in `check.sh`. Check first which specs compare that skill's text (a section that must be identical across skills cannot take a sentence for one of them).
