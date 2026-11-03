# Answers to design-review-008
- F1: fixed: the backticks in check.sh's AC1/AC2/AC5 labels are gone ("before ./zn done only"); consequences: none. Verified by running ./zn check afterwards (no command-substitution line).
- F2: fixed as a record, not as new behaviour: E18 records the experiment and the stated gap (Design "Limits of the design" and E1's neighbour), with the fallback (a wall bound for the hook entry) named and left to the user/lead, because adding it changes behaviour the capture does not ask for; consequences: none for the rules table; the proofs keep pure user-mode spinners and say so. Reported to the lead.
- F3: fixed: the Problem splits what the user decided from the open question (are the promoted proof files deleted after done); consequences: if yes, the executor's last step deletes them (the check.sh clauses are already inert).
- F4: fixed: "once" replaced by "before ./zn done" in AC5 and the six headers/labels.
- F5: fixed: recordedGone signals a pid only if its ps command line is under z-nile/.
- F6: fixed: spinner-bound wording (alarm 20 / os.clock), docs 11 and reap 18 cases, E17 and the rows now say C and D ran (B did not), step 4 verifies with the reap-e2e command.
