# Idea review 001

## Findings

- F1: The second Solution sentence can't be judged true or false for a model row that totals mixed spend rows. A per-model row adds up many spend rows. The sentence says "a row's minutes are its wall time where AI time could not be read, and `?` where neither could be read", but it doesn't say whether the fallback applies to each spend row before summing or to the total. It also doesn't say whether a model whose rows are partly read, partly wall-only and partly unread (each ledger `Row` has optional `ai` and `wall`, `z-nile/engine/ledger.luau:29-31`) shows a sum or `?`. And it doesn't say which of the two minute columns it changes. If it is the "measured AI minutes" column from the first sentence, that column would quietly mix in wall time under an AI label.

## Verdict

revise
