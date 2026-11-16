# Idea review 001

## Findings

- F1: The Problem sentence is false as written, so the Solution would fix a conflict that isn't there. Both rules it names check only the sequestered folders before promotion. The code-review sequestration check (`z-nile/skills/zz-review/SKILL.md:106`) and the test skill's copy of it (`z-nile/skills/zz-test/SKILL.md:91`) run `git diff` on `tracker/**/acceptance/**` and `*/.tracker/**/acceptance/**`. Neither looks at the promoted folder `tests/acceptance/<id>/`, which is where `./zn finish` writes `watch.txt` (`zz-test/SKILL.md:53`, `:57`). So neither rule forbids the watch file. Also, no lesson on `origin/main` says the acceptance watch file is "generated and legitimate"; I found only `zz-test/SKILL.md:57`, which calls finish "the only writer". The one rule that does cover the promoted folder is `zz-test/SKILL.md:39` ("Never edit these"), and the idea doesn't name it. The Problem needs to name the rule that actually blocks the watch file and the lesson it contradicts, or the idea should be dropped.

## Verdict

revise
