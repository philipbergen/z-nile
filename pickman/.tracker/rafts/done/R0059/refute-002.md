# Refute 002: R0059 (code mode)

- F1: fixed: the file stays in `tests/unit/plain/`, and its deviation line in c0153's Verification log says why it breaks the unit tier's rule (it requires `@tests/lib/plain`; no tier holds specs of a tests/lib helper yet) and names the captured follow-up, c0170 (a tier for tests/lib helper specs). Consequences: none.
- Notes: 30ca7219 is a 2-minute spend row, not empty (my report was wrong). The eps-0 subcase's comment in the sequestered plain.spec says it depends on Lune's decoder losing the ulp; the reviewer reads it as independent of the decoder. The spec is sequestered, so the comment stays as it is; if the reading is right, it is a wording fix for a later chore.
