# Trace: R0148

Commit: 220d41becbc7c53d93dae2b8b3b56a988678ed27

## Claims

| claim | design | test | code |
|---|---|---|---|
| d0405:P1: A busy answer from `Wallet` (`arcade/src/server/Wallet.luau`) always clears the pass allowance, so a PLAY that is still busy after the portal's 10-second wait (`Play.CHECK_SECONDS`) writes no pass, and a player with nothing to pay with is teleported to the game place and sent back without being offered the purchase. |  |  |  |
| d0405:S1: A busy answer keeps the pass allowance when the read in progress for that player and title is late, meaning its store call was not back within `Wallet.WAIT_SECONDS` (5 seconds, the Wallet's own late flag), so a PLAY pressed during a slow store call ends with a pass written or the purchase offered. |  |  |  |
| d0405:AC1: `tests/place/wallet-order.spec.luau` |  |  |  |
| d0405:AC2: None. |  |  |  |
| d0405:AC3: None. |  |  |  |

## Source files

| file | claims |
|---|---|
| arcade/src/server/Wallet.luau |  |
