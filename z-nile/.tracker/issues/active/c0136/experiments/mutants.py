#!/usr/bin/env python3
"""c0136 prep mutation runner.  python3 mutants.py [id ...]   (no id: every mutant)

Builds its own throwaway clone (mktemp -d) of the checkout this file sits in, applies prototype.patch to it, copies
the acceptance specs to z-nile/tests/acceptance/c0136 there, then applies each mutant to the clone's source, runs the
mutant's spec from the clone's z-nile/ folder (time-bounded) and prints KILLED (a spec case failed) or SURVIVED. The
clone is deleted at exit. Reads the real checkout only (git clone, the patch and the specs); writes nothing in it.
"""
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
L = "z-nile/engine/lessons.luau"
M = "z-nile/engine/main.luau"
T = "z-nile/engine/trail.luau"
C = "z-nile/engine/compact.luau"
# (id, file, old text, new text, spec)
MUTANTS = [
    ("M1", L, "entry.erred, entry.upstream, stepProblem = parseSteps(inner)\n\t\t\tif stepProblem then\n\t\t\t\ttable.insert(problems, `{item}/harvest.md: {key}:",
     "local _e, _u\n\t\t\t_e, _u, stepProblem = parseSteps(inner)\n\t\t\tif stepProblem then\n\t\t\t\ttable.insert(problems, `{item}/harvest.md: {key}:", "parse"),
    ("M2", L, "if base and inner then", "if false and base and inner then", "parse"),
    ("M3", L, 'target = string.match(rest or "", "^:%s*(.-)%s*$")', "target = nil", "parse"),
    ("M4", L, "if upstream == erred then", "if false then", "parse"),
    ("M5", L, 'if entry.erred == "none" and #entry.lessons > 0 then', "if false then", "parse"),
    ("M5b", L, 'elseif entry.erred == "none" then', "elseif false then", "parse"),
    ("M6", L, "if skill ~= erredNow and skill ~= upNow then", "if skill ~= erredNow then", "check"),
    ("M6b", L, "if skill ~= erredNow and skill ~= upNow then", "if false then", "check"),
    ("M7", L, 'if step ~= "none" and not tree.skills[canon(step, tree.skills)] then', "if false then", "check"),
    ("M8", L, "if canon(erred, tree.skills) ~= said.erred or entryUp ~= said.upstream then", "if canon(erred, tree.skills) ~= said.erred then", "check"),
    ("M8b", L, "if said and erred ~= nil", "if false and said and erred ~= nil", "check"),
    ("M9", L, "elseif used then", "elseif false then", "parse"),
    ("M10", L, "if into[current] ~= nil then", "if false then", "parse"),
    ("M11", L, "if e.erred == nil then\n\t\t\t\ttable.insert(", "if e.erred == nil and not e.note then\n\t\t\t\ttable.insert(", "sources"),
    ("M11b", L, "for _, item in byId(items) do\n\t\tfor _, e in entriesOf(item) do\n\t\t\tif e.erred == nil then", "for _, item in items do\n\t\tfor _, e in entriesOf(item) do\n\t\t\tif e.erred == nil then", "sources"),
    ("M12", M, '\t\t\tor a == "--unattributed"\n', "", "cli"),
    ("M13", L, '\t\tor string.match(stem, "^stream%-review%-[fdc]%d%d%d%d%-%d%d%d$") ~= nil -- c0136\n', "", "sources"),
    ("M13b", L, '\t\tor string.match(stem, "^focused%-review%-%d%d%d$") ~= nil -- c0136\n', "", "sources"),
    ("M14", T, '\t\t\t"^focused%-review%-%d+%.md$",\n', "", "sources"),
    ("M15", L, 'head, ids = string.match(line, "^(%- %S+ F%d+[^:]*:%s*)(.*)$")', 'head, ids = string.match(line, "^(%- %S+ F%d+:%s*)(.*)$")', "parse"),
    ("M16", L, 'local u: string? = if up == "none" then nil else up', "local u: string? = up", "parse"),
    ("M17", L, "add(`{item.id}/{lp.stem}.md {lp.text}`)", "local _ = lp", "check"),
    ("M19", M, "if modes > 0 and (n > 1 or (not", "if modes > 0 and (false or (not", "cli"),
    ("M20", M, "\t\t\telse lessonsLib.unattributed(items)", "\t\t\telse lessonsLib.uncovered(items)", "cli"),
    ("M21", L, "(designStep or (designReview and not ownMistake))\n", "(false)\n", "check"),
    ("M22", L, 'lessons.DESIGN_STEPS = { "z-ticket", "z-design", "z-raft" }', 'lessons.DESIGN_STEPS = { "z-ticket", "z-design" }', "check"),
    ("M23", L, "or (upNow ~= nil and table.find(lessons.DESIGN_STEPS, upNow) ~= nil)", "", "check"),
    ("M24", L, '"^stream%-review%-[fdc]%d%d%d%d%-%d%d%d$"', '"^stream%-review%-"', "sources"),
    ("N1", L, "(designStep or (designReview and not ownMistake))\n", "(designStep)\n", "check"),
    ("N2", L, 'local ownMistake = erredNow == "zz-review" and skill == "zz-review"', "local ownMistake = false", "check"),
    ("N3", L, 'if string.match(stem, "^design%-review%-") then\n\t\treturn "design"', 'if string.match(stem, "^design%-review%-") then\n\t\treturn "build"', "check"),
    ("N4", L, "if not waived[`{lp.stem} {lp.finding}`] then", "if true then", "check"),
    ("N5", L, "if not waived[`{lp.stem} {lp.finding}`] then", "if next(waived) == nil then", "check"),
    ("N6", L, "\t\tif fences then\n", "\t\tif false then\n", "parse"),
    ("N7", L, '\t\tif string.sub(line, 1, 3) == "## " then\n\t\t\tcurrent = nil -- a section after the findings (Judged criteria) is no finding\'s\n\t\t\tcontinue\n\t\tend\n', "", "parse"),
    ("N8", L, '\tif erred == "none" and upstream ~= nil then', "\tif false then", "parse"),
    ("N9", L, "local problem = validSteps(e, u)", "local problem = nil", "parse"),
    ("N10", L, "\t\t\tif skills then", "\t\t\tif false then", "parse"),
    ("N11", M, "compactLib.moveStreams(\".\", folders, { [old] = new :: string })", "local _ = folders", "renumber-streams"),
    ("N12", C, 'if process.exec("git", { "ls-files", "--error-unmatch", from }, { cwd = root }).ok then', "if true then", "renumber-streams"),
    ("N13", C, '(kind == "review" or kind == "refute")', 'kind == "review"', "renumber-streams"),
    ("N14", C, "local new = if id then map[id] else nil", 'local new = if id then (map[id] or "c0590") else nil', "renumber-streams"),
    ("N15", C, "compact.moveStreams(root, folders, map)", "local _ = folders", "renumber-streams"),
    ("O1", L, "local headStem: string? = if e.note then noteStem else e.review", "local headStem: string? = if e.note then nil else e.review", "check"),
    ("O2", L, "\t\treturn headingPhase(text)\n", '\t\treturn "build"\n', "check"),
    ("O3", L, "\t\treturn headingPhase(text)\n", '\t\treturn "design"\n', "check"),
    ("O4", L, "out[id] = { erred = canon(e, skills), upstream = if u then canon(u, skills) else nil }", "out[id] = { erred = e, upstream = u }", "check"),
    ("O5", L, "if e ~= \"none\" and not skills[canon(e, skills)] then", "if e ~= \"none\" and not skills[e] then", "check"),
    ("O6", L, "local erredNow = canon(erred, tree.skills)", "local erredNow = erred", "check"),
    ("O7", L, 'for _, key in { "erred", "upstream" } do', "for _, key in {} do", "parse"),
    ("O8", L, "if e.erred ~= \"zz-review\" then\n\t\t\t\t\tadd(`{who}: a waiver note", "if false then\n\t\t\t\t\tadd(`{who}: a waiver note", "check"),
    ("O8b", L, "elseif not stepProblems[stem][finding] then", "elseif false then", "check"),
    ("O8c", L, "elseif not item.reviews[stem] then\n\t\t\t\t\tadd(`{who}: no {stem}.md in {item.id}`)\n\t\t\t\telseif not stepProblems", "elseif false then\n\t\t\t\t\tadd(`{who}: no {stem}.md in {item.id}`)\n\t\t\t\telseif not stepProblems", "check"),
    ("O9", L, 'for stem, phase in phaseOf do\n\t\t\tif phase == "none" then', 'for stem, phase in phaseOf do\n\t\t\tif false then', "check"),
    ("O10", M, "lessonsLib.checkNewReview(stem, text, tree.skills)", "lessonsLib.checkNewReview(stem, text)", "cli"),
    ("O11", M, '\t\t["--check-review"] = true,\n', "", "cli"),
    ("O12", C, "\tfor _, m in streams do\n\t\tmv(m.from, `{m.to}.compacting`)\n\tend\n\tfor _, m in streams do\n\t\tmv(`{m.to}.compacting`, m.to)\n\tend\n", "\tfor _, m in streams do\n\t\tmv(m.from, m.to)\n\tend\n", "renumber-streams"),
    ("D10", "z-nile/skills/zz-review/SKILL.md", "A round with no step lines at all is not finished", "A round with no step lines is fine", "docs"),
    ("D11", "z-nile/skills/zz-review/SKILL.md", "Every finding of a design review is a mistake made in design", "Every finding of a design review is a finding", "docs"),
    ("D12", "z-nile/skills/z-design/SKILL.md", "a new round without them goes back to its reviewer", "a new round without them is harvested as it is", "docs"),
    ("D13", "z-nile/skills/zz-execute/SKILL.md", "names `Upstream: z-design`", "names a step", "docs"),
    ("D14", "z-nile/skills/zz-review/SKILL.md", "except a lesson filed under `zz-review` for the reviewer's own mistake, must be", "must be", "docs"),
    ("D15", "z-nile/skills/zz-rules/SKILL.md", "`./zn lessons --check-review <path>` checks one new review's step lines (a file with findings and none is refused) and its focused heading, wherever it is.", "", "docs"),
    ("D16", "z-nile/skills/zz-review/SKILL.md", "when the mistake sits in something design wrote", "when the mistake sits somewhere", "docs"),
    ("P1", L, 'return if word == "design" or word == "build" then word else "none"', 'return word or "none"', "check"),
    ("P2", L, 'and (headPhase ~= "build" or designFinding)', 'and (headPhase == "design" or designFinding)', "check"),
    ("P3", L, "phaseOf[stem] = word", "local _ = word", "check"),
    ("P4", L, 'elseif phaseOf[stem] ~= "none" then', "elseif false then", "check"),
    ("P5", L, "add(`{who}: no {noteStem}.md in {item.id}`)", "local _ = noteStem", "check"),
    ("P5b", L, "elseif not table.find(lessons.findings(review), noteFinding) then", "elseif false then", "check"),
    ("P6", L, "if skills and skills[name] then\n\t\treturn name", "if false then\n\t\treturn name", "check"),
    ("P7", L, "or #indent > 3 or", "or #indent > 9 or", "parse"),
    ("P8", L, "\tif open then\n", "\tif false then\n", "parse"),
    ("P9", L, "elseif fence ~= nil and c == fence and n >= fenceLen and", "elseif fence ~= nil and c == fence and", "parse"),
    ("P10", L, "elseif fence ~= nil and c == fence and n >= fenceLen and", "elseif fence ~= nil and n >= fenceLen and", "parse"),
    ("P11", L, "if #findings > 0 and next(steps) == nil and #problems == 0 then", "if false then", "parse"),
    ("P12", L, 'or string.find(first, "(focused mode", 1, true)', "", "parse"),
    ("Q1", L, 'local ownMistake = erredNow == "zz-review" and skill == "zz-review"', 'local ownMistake = erredNow == "zz-review"', "check"),
    ("Q2", L, "if tries and not phaseNote then", "if false then", "check"),
    ("Q2b", L, 'local tries = words[1] ~= nil and string.find(words[1], "review-", 1, true) ~= nil', "local tries = false", "check"),
    ("Q2c", L, "if e.note and e.erred ~= nil and noteStem == nil then", "if e.note and noteStem == nil then", "check"),
    ("Q3", L, "if said and erred == nil then", "if false then", "check"),
    ("D17", "z-nile/skills/zz-rules/SKILL.md", "in the folder of the `harvest.md` its lead writes in: the issue's during prep, the raft's during a raft's execution, whatever item it concerns)", "in the folder of the item it concerned)", "docs"),
    ("D18", "z-nile/skills/zz-review/SKILL.md", "(folder: zz-rules skill, Items)", "(the folder of the item the review concerned)", "docs"),
    ("D19", "z-nile/skills/zz-execute/SKILL.md", "a candidate lesson of a report as `- note ws-<issue> (erred <skill>): <lesson ids>`", "a candidate lesson of a report as `- note ws-<issue>: <lesson ids>`", "docs"),
    ("D20", "z-nile/skills/z-design/SKILL.md", "only a lesson filed under `zz-review` for the reviewer's own mistake is exempt", "only `erred zz-review` is exempt", "docs"),
    ("R1", L, "and (headPhase ~= \"build\" or designFinding)", "and headPhase ~= \"build\"", "check"),
    ("R2", L, "local designFinding = designKey ~= nil and findingDesign[designKey] == true", "local designFinding = false", "check"),
    ("R3", L, "if not e.note and (isDesignStep(e.erred) or isDesignStep(e.upstream)) then", "if false then", "check"),
    ("R4", L, "if isDesignStep(bound.erred) or isDesignStep(bound.upstream) then", "if false then", "check"),
    ("R5", L, "for i = 1, #words do", "for i = 1, math.min(3, #words) do", "check"),
    ("D21", "z-nile/skills/zz-review/SKILL.md", "a mistake an earlier round missed names the step that made it, with `Upstream: zz-review`", "a wrong or missed finding", "docs"),
    ("D1", "z-nile/skills/zz-test/SKILL.md", "A lesson goes to the step that erred", "A lesson goes to the step that ran", "docs"),
    ("D2", "z-nile/skills/zz-review/SKILL.md", "Erred: <skill, or none>\nUpstream: <earlier skill, or none>\n", "Upstream: <earlier skill, or none>\nErred: <skill, or none>\n", "docs"),
    ("D3", "z-nile/skills/z-design/SKILL.md", "`./zn lessons --uncovered <id>`, `./zn lessons --unattributed <id>` and", "`./zn lessons --uncovered <id>` and", "docs"),
    ("D4", "AGENTS.md", "each under the step that erred (`(erred <skill>)`", "each under the skill it improves (`(erred <skill>)`", "docs"),
    ("D5", "z-nile/skills/zz-execute/SKILL.md", "`./zn lessons --uncovered R0010`, `./zn lessons --unattributed R0010` and `./zn lessons --check` must pass", "`./zn lessons --uncovered R0010` and `./zn lessons --check` must pass", "docs"),
    ("D6", "z-nile/skills/zz-rules/SKILL.md", "`focused-review-NNN` (a focused review", "`focused-x` (a focused review", "docs"),
    ("D7", "z-nile/skills/zz-review/SKILL.md", "## Focused mode (any review outside a design or code round)", "## Other mode (any review outside a design or code round)", "docs"),
    ("D8", "z-nile/skills/zz-rules/SKILL.md", "step lines invalid", "step lines broken", "docs"),
    ("D9", "AGENTS.md", "z-design, z-raft and zz-execute harvest", "z-design and zz-execute harvest", "docs"),
]


def run(cmd, cwd, check=True):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"{' '.join(cmd)} failed in {cwd}: {r.stderr}{r.stdout}")
    return r


def main(only):
    tmp = tempfile.mkdtemp()
    try:
        clone = os.path.join(tmp, "proto")
        run(["git", "clone", "-q", "--no-hardlinks", ROOT, clone], ROOT)
        run(["git", "remote", "remove", "origin"], clone)
        run(["git", "apply", os.path.join(HERE, "prototype.patch")], clone)
        specs = os.path.join(clone, "z-nile/tests/acceptance/c0136")
        os.makedirs(specs)
        acc = os.path.join(HERE, "..", "acceptance")
        for name in os.listdir(acc):
            shutil.copy(os.path.join(acc, name), specs)
        run(["git", "add", "-A"], clone)
        run(["git", "-c", "user.name=prep", "-c", "user.email=prep@example.invalid", "commit", "-q", "-m", "proto"], clone)
        for mid, f, old, new, spec in MUTANTS:
            if only and mid not in only:
                continue
            path = os.path.join(clone, f)
            src = open(path).read()
            if src.count(old) != 1:
                print(mid, "NOT APPLIED (count %d)" % src.count(old))
                continue
            open(path, "w").write(src.replace(old, new))
            try:
                r = run(["perl", "-e", "alarm shift; exec @ARGV", "280", "lune", "run", "tests/run", "--",
                         f"tests/acceptance/c0136/{spec}.spec.luau"], os.path.join(clone, "z-nile"), check=False)
                out = (r.stdout + r.stderr).splitlines()
                fails = [l for l in out if l.startswith("FAIL")]
                summary = [l for l in out if "passed" in l][-1:]
                print(mid, spec, "KILLED" if fails else "SURVIVED", summary, [x[:140] for x in fails][:1])
            finally:
                open(path, "w").write(src)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main(sys.argv[1:])
