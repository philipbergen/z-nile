# Idea review 001

## Findings

- F1: None of the Solution sentences says that claims, releases and status changes stop being commits pushed to main. That leaves the first Problem unsolved. The last Solution sentence keeps "durable outcomes" in git but never says whether a claim counts as one. So a reader can't tell whether a claim still costs a push once this ticket is done. There is a related point about the second Problem. It says nothing records which activity a worker holds, but `./zn work next` already writes `.cache/work/carriers.tsv`. That file records which ticket or raft each session holds, though not its CLI or the single activity. f0399 also notes that c0265's heartbeat is meant to replace that file, so the existing record and c0265 should both be named.

## Verdict

revise
