# Idea review 003

## Findings

- F1: The fourth Solution sentence builds a landing gate that c0316 already designs, and the c0316 non-goal doesn't fence it off. c0316's Solution says "`./zn land` refuses work that has an escape with no harvest entry, where an entry names the stage that should have caught it and a lesson, or `one-off: <reason>`". Its Scope decision "The three gates" puts that refusal on `status prepared`, `ready` and `done`, and its plan for F10 makes a defect name `reworks:`, which makes the defect an escape. So under c0316 a defect already cannot land without a recorded stage and lesson. This idea adds a second record for the same escape: three per-stage answers held "in the ticket". Lessons don't live there. They are files in a skill's `lessons/` folder, and where each came from goes in `harvest.md` (zz-rules, Items). That breaks the idea's own rule that each thing is "written in one place". The non-goal says c0316's rule "is used as it stands", but c0316 is not on main (its design is `draft`, parked after design review 001), and f0448 has `depends_on: []`. So the non-goal leans on a rule nothing makes exist first, and it only fences off the `reworks:` part, not the gate. The smaller solution: depend on c0316 and require its escape entry for a defect to cover each of idea, design and code, with a lesson or a `one-off` for each stage.

## Verdict

revise
