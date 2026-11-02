# Answers to design-review-003 (c0184)

- F1: fixed: homes.spec gains a case that runs the home rule on the real tree for every registered project but z-nile, pickman among them, from z-nile (the net under the per-home specs: a neutered `snake/tests/run.luau` fails it, run). It is the one deliberate exception to specs-pin-only-their-own-project, and Design 1 says why: it is selected by `projects.toml` and the library, not by an edit to a home, and the merge's full gate runs it. A gate stage (the other option) would override c0114 gate-cover and c0120 gate-homes for no more safety than this case gives. Consequences: a Rules row; the written-down gap is now only what `--affected` does not select, caught at the merge.
- F2: fixed: skills.spec asserts that `skills.bases` is empty for z-nile, for pickman and for no project, and that z-nile's and pickman's prompts hold no snake or pickman base; mutant (the project filter dropped) killed.
- F3: fixed: `home.spec.luau` is named in the README's home list, zz-test's Spec layout sentence (pinned by docs.spec), the five `-test` skills, and Design ("three meta specs").
- F4: fixed: `t.luau` is held to its five lines like the other wrappers.
- F5: fixed: the prompt case moved into skills.spec, whose cases are AC6 as check.sh runs it; the Test plan names the cases that exist.
- F6: fixed: the home rule finds links inside a mapped folder (`find -type l`) and reports one that leaves the home (a `ping` fixture case; a snake link into pickman, run: killed).
- F7: fixed: the gap lists `stylua.toml`, `selene.toml`, `.tracker/architecture.md`, `skills/` and keep-files, and says check.sh and skill-text edits are caught only by the merge's full gate (`./zn skills --check` covers a skill's name and its `extends`).
- F8: fixed: `skills.plan` refuses `extends:` on a z-nile skill and a base that itself extends (one level); skills.spec pins both, mutants killed.
