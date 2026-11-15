# Idea review 001

## Findings

- F1: The second audit rule contradicts the problem and the Duplicates bullet. The audit fails when an item is closed as delivered while the item it names is not done. c0371 is still being designed (`design: draft`, `status: preparing-…`), so closing c0141 with the new command today makes the gate's audit fail. That leaves c0141 in the backlog, where z-design can claim it, until c0371 is done, which is the problem this idea is meant to fix. The same rule applies at capture: the item a duplicate is merged into is almost never done yet, so the Duplicates bullet's "record it as delivered by the surviving item" would fail the audit in nearly every case it describes.

## Verdict

revise
