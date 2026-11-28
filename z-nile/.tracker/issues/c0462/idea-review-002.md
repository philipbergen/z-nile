# Idea review 002

## Findings

- F1: The exemption covers only "cases in the acceptance specs" of a listed item, but listed items also own pinned proof specs that `check.sh` runs through `tests/run`, and some of their cases make no `t.expect` call. Examples are "sets up claims and the shim" in `z-nile/.tracker/issues/active/c0265/proofs/race.spec.luau`, and the setup cases in c0275's `proofs/long.spec.luau`, `beater.spec.luau` and `dispatch.spec.luau`. Those files are hash-pinned in c0265 AC4 and c0275 AC3, and the first non-goal forbids editing any spec file of a listed item. As written, these cases would start failing with no permitted fix, so the Solution contradicts the non-goal and its own "stay green" claim for items still in `active/`.
- F2: "Written once, when this issue lands, and holds every item that has acceptance specs at that moment" names a moment at which nothing writes the file. The list is checked in on the layer branch, before review and the merge. A reader cannot tell whether "that moment" is the write or the merge. An item whose prep merges in between has specs written under the old runner, is not on the list, and its sequestered specs cannot be edited. The idea names nothing that makes the sentence true at the merge.

## Verdict

revise
