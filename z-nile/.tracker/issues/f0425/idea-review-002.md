# Idea review 002

## Findings

- F1: Solution sentence 2 is false as written. `mockup/index.html` lines 7 to 9 preconnect to `fonts.googleapis.com` and `fonts.gstatic.com` and load a stylesheet from Google Fonts, so opening the page makes network requests. Sentence 4's three fonts depend on those requests. Only the narrower claim holds: the script uses none of the four named APIs, and nothing reaches the tracker or the daemon.
- F2: The stage half of Solution sentence 3 cannot be found true. `openSendBack` (line 2587) opens the form with a stage already selected, and a radio group cannot be unselected, so the form submits without the owner picking one. `submitSendBack` refuses only an empty instruction. `sendBackStages` also disables any stage the ticket has not reached, so idea, design and code are not always all on offer.
- F3: The Solution names only the Approvals view, but the mockup also holds Workers, Stats, Tickets and Rafts views on simulated data. They are in the ticket's recorded owner decisions of 2026-11-21 (PRs #716 and #719), and f0437's Problem relies on them being f0425's. They appear neither as an outcome nor as a non-goal, though sentence 4's "chart colours" already leans on the Stats view. A reader cannot tell whether they are in this ticket, and dropping them is a scope cut that needs the owner.
- F4: Non-goal 3 fences `zn talk`, but nothing fences `zn rework`. The send-back confirmation shows and copies `zn rework <id> --stage … --note … --lesson` as "the command it stands for" and offers "Also record this as a lesson". f0437's G15 says `./zn rework` does not exist on main, so this is the same kind of simulated control with no fence.

## Verdict

revise
