# Idea review 003

## Findings

- F1: The last Problem bullet says `.cache/board.html` is rebuilt "in `buildBoard` ... on a publish or `land`", and that checks false. `buildBoard` has one caller, `cmd.sync` in the main checkout (`z-nile/engine/main.luau` line 2649). The comment at lines 679-680 says a publish "does not fast-forward the main checkout, sweep it, or rebuild the board". `cmd.land` (lines 2826-3001) never calls `buildBoard`, `sync` or `pullMain`. `./zn board` writes the page itself (lines 8751-8757), and zz-rules line 90 agrees: "rebuilt by `./zn board` and by `./zn sync` there (a tracker push does not rebuild it)".

## Verdict

revise
