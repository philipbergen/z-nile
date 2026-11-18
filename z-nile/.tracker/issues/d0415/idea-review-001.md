# Idea review 001

## Findings

- F1: The fourth Solution sentence doesn't fix the third Problem, because "its run's state folder" doesn't exist. The dispatcher keeps one state folder per item, `{dispatcher.home}/{target}` (`z-nile/engine/dispatcher.luau:1103`), and every run of that item first deletes any `review.md` left there (`z-nile/engine/dispatcher.luau:903`). So the next dispatch of the same raft, which is exactly the retry a refusal leads to, deletes the review this sentence promises to keep. Its findings are lost anyway. The sentence needs a place that a later run of the same item doesn't clear, for example a numbered name like the `review-attempt-N.md` already used at `z-nile/engine/dispatcher.luau:1038`.

## Verdict

revise
