# Idea review 001

## Findings

- F1: The Solution and the Non-goal both depend on "late", and the idea never defines it. The only wait the Problem names is the portal's 10 seconds (`Play.CHECK_SECONDS`), but the Wallet's own late flag is set when its store call isn't back within `Wallet.WAIT_SECONDS`, which is 5 seconds (`arcade/src/server/Wallet.luau:19`, `:287`). Take a busy answer given 7 seconds into a read. If "late" means past the Wallet's 5 seconds, it keeps the allowance. If it means past the portal's 10 seconds, it clears it. A reader can't tell which, so the Solution and the Non-goal can't be checked true or false. Saying "late: not back within the Wallet's 5-second wait" would settle it. The Non-goal itself is a real fence: it keeps two specs passing (`arcade/tests/place/wallet-order.spec.luau:291` and `arcade/tests/acceptance/f0201/wallet.spec.luau:1029`) that a smaller "busy never clears the allowance" fix would break.

## Verdict

revise
