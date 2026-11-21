# Idea review 001

## Findings

- F1: The second Solution bullet can't be judged true or false for every existing item, because some items have no correct stage among the six. An issue closed as won't do (`status: closed`, set by `./zn close`) and a retired raft (`z-nile/.tracker/rafts/retired`) are at none of idea, design, code, review, approval or landed. Showing them at "the correct one of the six" forces a wrong stage. The first bullet ("no other word is used") also rules out keeping "closed" as a separate word. The idea has to say how items that left the flow without landing are shown: as a seventh, terminal word, as hidden, or in some other way.

## Verdict

revise
