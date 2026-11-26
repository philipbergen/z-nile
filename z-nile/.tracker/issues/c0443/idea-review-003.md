# Idea review 003

## Findings

- F1: The 25-ticket list is incomplete, so the Solution's last clause is false. The Solution repoints only acceptance specs, but six unlanded tickets read `z-nile/README.md` directly from their `check.sh`. Five are active: c0265 (lines 25 and 27: the Order section and the roadmap row), c0274 (line 25), c0275 (line 22), c0276 (line 21: the board paragraph) and c0277 (line 33). The sixth is c0256 in the backlog (line 25: `has README.md '`./zn dispatch retry <id> --answer <text>`'`). The active ones point `R="$ZN_ROOT/z-nile"` at `"$R/README.md"`. None of the six is in the list, and none of their `check.sh` files is a spec the ticket repoints. After this ticket lands, those checks would fail on the short README.md, or still read the reference text from it. The Problem's "25 unlanded tickets" count is too low for the same reason.

## Verdict

revise
