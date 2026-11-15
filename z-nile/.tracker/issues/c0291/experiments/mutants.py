#!/usr/bin/env python3
# c0291 prep mutation check: applies each Rules-and-mutants row's mutant to the prototype worktree given as argv[1]
# (its z-nile/tests/tooling/ holds copies of this issue's acceptance specs), runs the row's spec file, and records
# whether the run failed on an assertion. Restores the file after each row. Run through ./zn run.
import subprocess, sys, pathlib, re
root = pathlib.Path(sys.argv[1])
L, M, D, A = "z-nile/engine/lessons.luau", "z-nile/engine/main.luau", "z-nile/engine/dispatch.luau", ".gitattributes"
ROWS = [
 ("M1 noteName takes any date", L, "or not lessons.day(date) ", "", "notes"),
 ("M2 noteName takes any non-empty label", L, "or not kebab(label) ", 'or label == "" ', "notes"),
 ("M3 compose always ends the text with a newline", L, "\tif #notes == 0 then\n\t\treturn text\n\tend\n\tlocal sorted", "\tif #notes == 0 then\n\t\treturn if string.sub(text, -1) == \"\\n\" then text else text .. \"\\n\"\n\tend\n\tlocal sorted", "notes"),
 ("M4 compose keeps the order read", L, "\ttable.sort(sorted, function(a, b)\n\t\treturn a.name < b.name\n\tend)\n", "", "notes"),
 ("M5 compose puts no blank line before a note", L, "\tfor _, n in sorted do\n\t\ttable.insert(out, \"\\n\")\n", "\tfor _, n in sorted do\n", "notes"),
 ("M6 compose leaves a missing final newline", L, "\t\tif string.sub(n.text, -1) ~= \"\\n\" then\n\t\t\ttable.insert(out, \"\\n\")\n\t\tend\n", "", "notes"),
 ("M7 text ignores the notes", L, "\treturn lessons.compose(text, notes)\n", "\treturn text\n", "notes"),
 ("M8 search reads the file alone", M, "lessonsLib.parse(id, lessonsLib.text(tree, id) :: string)", "lessonsLib.parse(id, tree.lessons[id])", "notes-merge"),
 ("M9 --full prints the file alone", M, "stdio.write(lessonsLib.text(tree, l.id) :: string)", "stdio.write(tree.lessons[l.id])", "notes-merge"),
 ("M10 no orphan check", L, "\t\tif not tree.lessons[id] then\n\t\t\tadd(`{dir}/: notes with no lesson {slug or id}.md`)\n\t\tend\n", "", "notes"),
 ("M11 no note-name check", L, "\t\t\tif not lessons.noteName(n.name) then\n\t\t\t\tadd(`{dir}/{n.name}: not a note file (a note is <YYYY-MM-DD>-<label>.md)`)\n\t\t\telseif", "\t\t\tif false then\n\t\t\telseif", "notes"),
 ("M12 no empty-note check", L, "\t\t\telseif trim(n.text) == \"\" then\n\t\t\t\tadd(`{dir}/{n.name}: the note is empty`)\n", "", "notes"),
 ("M13 load leaves a notes folder 'not a lesson file'", L, "\t\t\t\t\telseif fs.isDir(`{folder}/{name}`) then\n", "\t\t\t\t\telseif false then\n", "notes-merge"),
 ("M14 load skips a folder inside a notes folder", L, "\t\t\t\t\t\t\t\ttable.insert(tree.problems, `{rel}/lessons/{name}/{n}: not a note file`)\n", "", "notes-merge"),
 ("M15 load reads hidden files as notes", L, "\t\t\t\t\t\t\tif string.sub(n, 1, 1) == \".\" then\n\t\t\t\t\t\t\t\tcontinue\n\t\t\t\t\t\t\telseif fs.isFile(path)", "\t\t\t\t\t\t\tif fs.isFile(path)", "notes-merge"),
 ("M16 isLesson takes lesson files only", D, "\t\tor string.match(\n\t\t\t\tpath,\n\t\t\t\t\"^[^/]+/skills/[^/]+/lessons/[a-z0-9][a-z0-9%-]*/%d%d%d%d%-%d%d%-%d%d%-[a-z0-9][a-z0-9%-]*%.md$\"\n\t\t\t)\n\t\t\t~= nil\n", "", "notes-paths"),
 ("M17 isLesson takes any depth", D, "\"^[^/]+/skills/[^/]+/lessons/[a-z0-9][a-z0-9%-]*/%d%d%d%d%-%d%d%-%d%d%-[a-z0-9][a-z0-9%-]*%.md$\"", "\"^[^/]+/skills/[^/]+/lessons/.+%.md$\"", "notes-paths"),
 ("M18 lessons merge by union (an attribute)", A, None, "z-nile/skills/*/lessons/*.md merge=union\n", "notes-merge"),
 ("M21 notes merge by union (an attribute)", A, None, "z-nile/skills/*/lessons/*/*.md merge=union\n", "notes-merge"),
 ("M22 load drops misnamed notes", L, "\t\t\t\t\t\t\tif string.sub(n, 1, 1) == \".\" then\n\t\t\t\t\t\t\t\tcontinue", "\t\t\t\t\t\t\tif string.sub(n, 1, 1) == \".\" or not lessons.noteName(n) then\n\t\t\t\t\t\t\t\tcontinue", "notes-merge"),
 ("M23 load drops empty notes", L, "\t\t\t\t\t\t\t\ttable.insert(list, { name = n, text = fs.readFile(path) })\n", "\t\t\t\t\t\t\t\tif trim(fs.readFile(path)) ~= \"\" then\n\t\t\t\t\t\t\t\t\ttable.insert(list, { name = n, text = fs.readFile(path) })\n\t\t\t\t\t\t\t\tend\n", "notes-merge"),
 ("M24 check parses the composed text", L, "\tfor id, text in tree.lessons do\n\t\tlocal l, err = lessons.parse(id, text)\n", "\tfor id, _ in tree.lessons do\n\t\tlocal l, err = lessons.parse(id, lessons.text(tree, id) :: string)\n", "notes"),
 ("M25 one skill keeps the old sentence", "z-nile/skills/zz-stats/SKILL.md", "It adds a note to an existing lesson when one fits (a file of its own in the lesson's notes folder, never a paragraph at the end of its file: zz-rules skill, Items), writes a new lesson only when none does,", "It adds a note to an existing lesson when one fits, writes a new file only when none does,", "notes-docs"),
 ("M26 isLesson takes any md in a notes folder", D, "lessons/[a-z0-9][a-z0-9%-]*/%d%d%d%d%-%d%d%-%d%d%-[a-z0-9][a-z0-9%-]*%.md$", "lessons/[^/]+/[^/]+%.md$", "notes-paths"),
 ("M27 isLesson takes any md as a lesson", D, "\"^[^/]+/skills/[^/]+/lessons/[a-z0-9][a-z0-9%-]*%.md$\"", "\"^[^/]+/skills/[^/]+/lessons/[^/]+%.md$\"", "notes-paths"),
 ("M28 docs drop the --full sentence", "z-nile/skills/zz-rules/SKILL.md", " (`--full` prints them after the file, under the file's path: the note files are the record, so never copy that text back into `<slug>.md`)", "", "notes-docs"),
 ("M19 docs keep the append habit", "z-nile/skills/zz-rules/SKILL.md", "never a paragraph added to the end of `<slug>.md`", "or a paragraph added to the end of `<slug>.md`", "notes-docs"),
 ("M20 docs drop the conflict sentence", "z-nile/skills/zz-rules/SKILL.md", " An edit to the lesson's rule, `check` or other frontmatter is still an edit of `<slug>.md`, and two such edits still conflict.", "", "notes-docs"),
]
only = sys.argv[2:] 
for name, rel, old, new, spec in ROWS:
    if only and name.split()[0] not in only:
        continue
    p = root / rel
    had = p.exists()
    orig = p.read_text() if had else None
    if old is None:
        if had:
            print(f"{name}: SKIP ({rel} exists)"); continue
        p.write_text(new)
        if rel == ".gitattributes":
            subprocess.run(["git", "add", "-N", rel], cwd=root)
    else:
        if orig.count(old) != 1:
            print(f"{name}: NOT APPLIED ({orig.count(old)} matches)"); continue
        p.write_text(orig.replace(old, new))
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", f"tests/tooling/{spec}.spec.luau"], cwd=root / "z-nile",
                           capture_output=True, text=True, timeout=600)
        out = r.stdout + r.stderr
        fails = [l for l in out.splitlines() if l.startswith("FAIL ") and "::" in l]
        syntax = re.search(r"(SyntaxError|error requiring|attempt to call a nil|TypeError)", out)
        verdict = "KILLED" if r.returncode != 0 and fails and not syntax else ("SURVIVED" if r.returncode == 0 else "ERROR")
        print(f"{name} [{spec}]: {verdict}" + ("".join(f"\n    {l}" for l in fails[:3])))
        if verdict == "ERROR":
            print("\n".join(out.splitlines()[-8:]))
    finally:
        if had:
            p.write_text(orig)
        else:
            if rel == ".gitattributes":
                subprocess.run(["git", "rm", "-q", "--cached", "-f", rel], cwd=root)
            p.unlink()
