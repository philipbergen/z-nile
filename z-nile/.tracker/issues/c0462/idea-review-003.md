# Idea review 003

## Findings

- F1: The Solution's "`--full` and `--slow` stay green" and the first Non-goal cannot both hold. Promoted specs of exempt items copy the working tree's `z-nile/tests/run.luau` and `tests/lib` into a `.cache` fixture and run fixture specs there whose cases make no assertions, then assert the run passed. `z-nile/tests/acceptance/c0058/lock.spec.luau` copies the runner at line 157, writes the probes `first` and `second` (lines 184 and 194, file writes only) and expects both runs ok at lines 233–234. Those probes sit at `tests/probe/*.spec.luau` in the fixture, under no item's folder, so the new runner fails them and the c0058 case flips to failing, in a file the Non-goal says is not edited. The same shape is in `c0058/fence.spec.luau` (the `env` probe, line 229) and in `c0165/gatefix.luau` (`slow1 = { hold = true }`, line 166), which is a helper and not a spec file, so the Non-goal's fence does not literally cover it. The idea does not say how a nested run of the copied runner on a fixture spec is treated.
- F2: "If main has moved by then, the rebase, the script and the gate run again" is larger than the risk it names, and may not end. Main took 44 commits in the last 24 hours, almost all tracker state, so a full gate will rarely finish on an unmoved main. The stated risk is only an item whose prep merged in the meantime. Rerunning the script on the new main and repeating the gate only when the list it writes differs would cover it.

## Verdict

revise
