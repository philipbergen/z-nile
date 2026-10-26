# Refute 002: f0125 (design mode)

- F1: fixed: the case accepts base 96 with k = 120/114 (level 5's ghost exactly 120), refuses 121/114, and accepts base 30 with k = 2 (71); KGT1 (any k > 1 refused) and `>=` are run rows, killed; "normal only" is recorded as an equivalent mutant; consequences: none (f0018's pins untouched).
- F2: fixed: the bound resolves `c.ghostTuning or Levels.GHOST_TUNING`, as `Session.speeds` does, so untuned configs are bounded too; the mutant that skips untuned configs is equivalent while GHOST_TUNING is 1 (recorded); consequences: base 96 untuned stays accepted (114).
- F3: fixed: review 001 F3's harvest entry now names the new lesson zz-test/refusals-tested-on-both-sides; consequences: none.
