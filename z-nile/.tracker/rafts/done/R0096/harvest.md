# Harvest: R0096
- review-001 F1 (erred z-design): one-off: one unreachable state of a carried row was not named in the design or the comment
- review-001 F2 (erred zz-execute, upstream z-design): z-design/restated-rules-move-together
- review-001 F3 (erred z-design): one-off: the design claimed one reader of a contract for two of its three builders; the comment now names all three (the rule itself is zz-arch one-reader-per-format)
- note two reds on the layer (a whole check's AC2 and a finish gate's six cases) could not be explained because their output had been cut to its last lines (erred zz-execute): zz-execute/keep-the-first-error-of-every-red
- final-review-001 F1 (erred none): one-off: main moved by tracker commits while the review ran, so the trace check saw an unstacked layer
- final-review-001 F2 (erred zz-execute): zz-execute/keep-the-first-error-of-every-red
- final-review-001 F3 (erred z-design): z-design/restated-rules-move-together
