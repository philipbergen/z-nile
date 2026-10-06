# Design refute 003: R0032
- F1: fixed: the legacy loop in `plan.spec` iterates `{ "UNSET", "" }` and maps the sentinel to an unset variable, so both the missing and the empty variable are tested. consequences: none.
