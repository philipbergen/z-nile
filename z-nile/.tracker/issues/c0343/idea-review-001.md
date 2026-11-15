# Idea review 001

## Findings

- F1: The fourth Problem bullet and the fourth Solution bullet duplicate c0300 ("Restack drops unfinished layer commits"). They also hang on a condition that can't be judged true or false, because they check the wrong issue. c0300's Problem already says restack "rebases only the layer's last commit onto the new main and drops the others" and that finish's refusal "leads straight into the truncating restack". Its fourth Solution bullet is the same outcome as this one: follow the command finish names, no hand rebase, then finish succeeds. d0331 lists c0300 as a non-goal. d0331 covers the first half: finish accepting layer one on any commit of main. So "if d0331 does not already cover it" can be settled now, and the answer is that c0300 covers it. The restack bullets don't belong in the smallest fix for the trace-table deadlock. The non-goal should fence them off by naming c0300, not leave them conditional on d0331.

## Verdict

revise
