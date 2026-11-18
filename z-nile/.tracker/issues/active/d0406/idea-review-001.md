# Idea review 001

## Findings

- F1: The fourth Solution bullet is bigger than the problem and fights existing code. The problem is two named phases, `idea` and `idea-challenge`. The bullet instead requires every reader to finish "without error when a row carries a phase it does not know", which is any phase at all. The spend.md reader rejects unknown phases on purpose: `ledger.parse` returns "unknown phase" at `z-nile/engine/ledger.luau:123`, and `ledger.append` raises at `:392`. As written, the bullet would force that check open. That works against the non-goal of not changing the spend-row format and against the tooling's rule that guards fail closed. It is also hard to test: once readers learn the two idea phases, it is unclear which phase counts as "unknown" in a test. The smallest fix is to make metrics and the other named readers know `idea` and `idea-challenge`, and leave unknown phases rejected. The third Problem bullet ("not proven to survive") states a missing proof, not an observed failure, so that bullet should also name only the two phases.

## Verdict

revise
