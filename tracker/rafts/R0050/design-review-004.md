# Review 004: R0050 (design mode)
Inputs: working tree on main @ 360511a (uncommitted): `tracker/rafts/R0050/{R0050-game-alias-requires.md,check.sh,design-review-00{1,2,3}.md,design-refute-00{1,2,3}.md}`, `tracker/issues/c0390/{c0390-game-alias-requires.md,check.sh,acceptance/*.spec.luau}`, `scripts/lib/graph.luau`, `scripts/check.sh`, `scripts/affected.luau`, `tests/lib/place.luau`, `tests/meta/architecture.spec.luau`, `tests/acceptance/c0020/*`, `.luaurc`, `stylua.toml`, `default.project.json`, the architecture/testing/tracker/review skills, `tracker/architecture.md`, R0040 raft and f0120/f0130 frontmatter (context). This is round 4, an extra round the user approved.
Dropped from review-003: F1, F2
Method: I built a fresh prototype of the c0390 Design in a scratch worktree (`/tmp/r0050-review4`, since removed). It had `gameRoots`, `resolveGame`, `srcAliasAllowed`, `srcAliasViolations` and the `resolve`/`build` pass-through in graph, the `@game` branch in place, the meta case formatting `file: spec`, and a minimal rule-5 skill edit. Results:
- c0390 `check.sh`: AC1, AC2, AC3 and AC5 pass. AC4 also passes once the skill carries the three phrases.
- R0050 `check.sh`: 4/4 pass (the full gate, c0390, promote-check and RC1).

Refute-003 answers verified against the files:
- **F1 (resolved).** The scan now lives in `graph.srcAliasViolations`, and `src-aliases.spec.luau:46-72` tests it against real files.
  - I reran review-003's scenario: a client `src/client/Bad.luau` doing `require( '@game/ServerScriptService/Server/Secret')`, plus `src/server/Secret.luau`. The spec now fails at line 77 (`srcAliasViolations("src")` is not `{}`), whatever the meta case does.
  - Once promoted to `tests/acceptance/c0390/`, the spec runs in every `--full` gate, so the permanent guard no longer depends on the meta case being correct.
  - Mutants: dropping `stripComments` fails 1 case, and allowing any `@game/` root fails 2 cases. The four mutants the refute lists are covered by the fixture: a single-quoted, spaced spec; a file in a subdirectory; a commented-out require; and an exact expected list.
  - A remaining gap I probed: a paren-less `require '…'` or `require"…"` escapes `REQUIRE_PATTERN`, and so every meta rule and RC1. It isn't a finding, because `stylua.toml` sets `call_parentheses = "Always"` and the gate's `stylua --check` rejects that form (verified). A `require([[…]])` long string is caught by the existing "no dynamic requires" rule.
- **F2 (resolved).** c0390 E3 now says four acceptance specs, 22 cases and 21 mutants, with refreshed sizes.

### F1 [low] Rule 5's surviving sentence "Roblox and Lune resolve them the same way" becomes false for `@game`
Where: c0390 Design, "Architecture skill (`.claude/skills/architecture/SKILL.md`), rule 5". The skill currently says at line 29: "Roblox and Lune resolve them the same way."
Evidence: the Design amends rule 5's heading to add `@game/ReplicatedStorage/` and adds a bullet, but it leaves the first bullet unchanged. Lune has no `@game` alias: only `graph.resolve`, which is repo tooling, maps it through `default.project.json`. A module that does `require("@game/…")` therefore can't be loaded by Lune at all. That's harmless today, since adapters are never loaded in Lune (the scenario tier forbids them). But the rule would claim a symmetry that no longer holds, right next to the new text.
Fix: in the rule-5 instructions, have the executor qualify that bullet. For example: "Relative and `@self` requires resolve the same way in Roblox and Lune; `@game` resolves only in Roblox (and in the repo's resolvers), so modules using it are never loaded from Lune specs."

Notes (no finding):
- **Affected mode**: neither `tests/meta` nor the promoted `src-aliases.spec` is selected by a `src/`-only change in `--affected` mode, because their closures don't include `src`. That was already true of every meta rule, and CI plus every raft `check.sh` run `--full`, so this raft doesn't need to change it.
- **Regressions**: with the prototype, the full gate is green: tooling, place, c0020 (including `resolve-require` pinning `@logic`/`@lune` → nil, and `place-rules`) and meta.
- **Raft coherence**: f0120 and f0130 list `c0390` in `depends_on`. R0040's Order step 0 and RC2 match the ReplicatedStorage-only contract.
- **Executability**: the Design, steps and checks are enough to deliver without asking a question.

Verdict: approve
