# Idea review 001

## Findings

- F1: The second Problem sentence is false within a raft, and it makes the third Solution sentence too broad. zz-rules (One layer per ticket) and zz-execute step 2 say each ticket already gets its own layer branch (`R0010/1/c0010`), each layer is built on the one below, and `./zn done` lands the whole stack with one `--no-ff` merge. So a dependent ticket in the same raft is already built on top of its prerequisite's branch, and the raft already merges as a stack. The gap is narrower than stated: (a) a raft that depends on a ticket in another, unapproved raft starts from `main` rather than from that ticket's layer; and (b) a ticket whose guess sits at the idea or design stage has no layer branch yet for anything to build on. As written, the Problem cannot be tested, and the Solution cannot say which branch dependent work starts from in case (b).

## Verdict

revise
