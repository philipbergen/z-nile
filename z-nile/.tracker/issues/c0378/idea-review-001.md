# Idea review 001

## Findings

- F1: The first Problem and Solution leave out one of the forms that c0371 lists in the same known edge. Its Known edges bullet reads "a cd to anything that is neither a root form nor a literal folder (`cd -`, `cd "$OLDPWD"`, `cd "$VAR"`, `cd "$(…)"`) changes nothing … (reports)". The ruled rule (a) is "a cd whose argument is neither a root form nor a literal folder resets its frame to the home". The idea names only a variable, `cd -` and `cd "$OLDPWD"`, so `cd "$(…)"` after a root cd would still report. That makes two of the idea's sentences contradict each other. The Solution says "The three shapes no longer appear in the reader's Known edges list", but that bullet would have to stay to cover `cd "$(…)"`. The first Non-goal says "This does not change any other entry", but that bullet is the same entry. c0378's own capture says "model them as main", so this is a narrowed scope, not a fence. Either cover every argument that is neither a root form nor a literal folder, as rule (a) does, or name `cd "$(…)"` as a non-goal and say that the entry stays shortened.

## Verdict

revise
