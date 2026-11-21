# Idea review 001

## Findings

- F1: The two Solution sentences disagree about a command like `cd x && make; ./zn gate`, and so a reader can't say true or false for that command. It has a cd followed by a semicolon and another command, so the first sentence refuses it. It also joins the cd to the next command with "&&", so the second sentence allows it. If it is allowed, the same failure from the Problem comes back: when `cd x` fails, `make` is skipped, but `./zn gate` still runs in the original folder. The Solution needs to say whether a semicolon or newline anywhere after a cd counts, or only one that comes straight after it. It also needs to say which side wins for that command.

## Verdict

revise
