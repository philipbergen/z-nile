# Idea review 003

## Findings

- F1: The leak check is the only proof that the leak is gone, but as written it could pass while the gate still leaks. "Within a stated tolerance" sets no bound on that tolerance. A tolerance of 5,000 meets the sentence, and every measured run so far added 3,400 to 4,900, so the current leaking gate would pass. The check also doesn't say when the "afterwards" reading is taken. Problem 2 only counts elements that stay after minutes of rest. A reading taken straight after the gate also counts elements the machine would free on its own, which can fail a gate that no longer leaks. A reader therefore can't tell from this sentence whether passing the check means the work is done. (I confirmed `zprint data.kalloc.1024` runs as the ordinary user, so the meter itself is feasible. I also found no existing reader of the zone and no skill guidance that limits gate runs, so Problems 4 and 6 hold.)

## Verdict

revise
