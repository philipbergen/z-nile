#!/usr/bin/env python3
"""c0226 mutation runner. Run with python3 -I, bounded: ./zn run --time 1500 -- python3 -I <this file> [<base>].

Clones the repository with --no-hardlinks into a fresh mktemp folder outside any checkout and removes the clone's
origin at once, so nothing in it can reach the real repository. Checks out BASE (prep's base; pass another revision as
the only argument, such as origin/main, to rerun on a later base), applies `prototype.patch` from this folder, copies
this item's acceptance specs in (found from this script's own path) and runs them unmutated (every case must pass).
Then, for each mutant of the Rules table, applies it in the clone, runs every spec it names, and requires every named
case to FAIL on an assertion ("expected ..."), not on a syntax or require error. The clone is removed at the end. It
runs in the caller's environment as it is: none of the specs it runs pushes.
"""
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
ITEM = os.path.dirname(HERE)
ACC = os.path.join(ITEM, "acceptance")
TOP = subprocess.run(["git", "-C", HERE, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                     capture_output=True, text=True, check=True).stdout.strip()
DIR = ".tracker/issues/c0226/acceptance"  # from the clone's z-nile home
RULE, CUTS, DOCS = (f"{DIR}/{n}.spec.luau" for n in ("rule", "cuts", "docs"))
HIST = "tests/acceptance/c0118/history.spec.luau"
BASE = sys.argv[1] if len(sys.argv) > 1 else "6d8cd0ff0477a50c7cbfac1a2c9b34bc33562241"
PATCH = os.path.join(HERE, "prototype.patch")

I, T, H = "z-nile/engine/ids.luau", "z-nile/engine/trail.luau", "z-nile/engine/history.luau"
L = "z-nile/skills/zz-rules/lessons/item-history-spans-moves-and-compaction.md"
LISTS = (CUTS, "AC2: trail.cuts lists every")
PARITY = (CUTS, "AC2: history counts as compactions exactly")
HISTORY = (HIST, None)  # any c0118 history case

BLOB_CUTS = '''local out: { [string]: string } = {}
	local sha = ""
	local commits: { [string]: { any } } = {}
	local argv = { "log", "--no-renames", "--diff-filter=AMDT", "--raw", "--no-abbrev", "--format=@@%H", head, "--" }
	for _, f in ids.MAP_FILES do
		table.insert(argv, f)
	end
	for line in string.gmatch(git(argv, dir) or "", "[^\\n]+") do
		local s = string.match(line, "^@@(%x+)$")
		if s then
			sha = s
			commits[sha] = commits[sha] or {}
		else
			local old, new, st, path = string.match(line, "^:%d+ %d+ (%x+) (%x+) (%u)%d*\\t(.+)$")
			if st then
				table.insert(commits[sha], { old = old, new = new, st = st, path = path })
			end
		end
	end
	for s, list in commits do
		local gone: { [string]: boolean } = {}
		for _, e in list do
			if e.st == "D" then
				gone[e.old] = true
			end
		end
		for _, e in list do
			if e.st == "M" or (e.st == "A" and not gone[e.new]) then
				out[s] = e.path
				break
			end
		end
	end
	return out'''

OWN_RULE = '''local file: string? = nil
			local anyDeleted = false
			for _, m in maps do
				if m.deleted then
					anyDeleted = true
				end
			end
			for _, m in maps do
				if (m.added and not anyDeleted) or (not m.added and not m.deleted) then
					file = m.path
					break
				end
			end'''

ADD_RETURN = 'if not gone[table.concat(m.plus, "\\n")] then\n\t\t\t\treturn m.path'

MUTANTS = [
    ("M1 an add beside any deletion is a move", I,
     [('if not gone[table.concat(m.plus, "\\n")] then', "if next(gone) == nil then")],
     [(RULE, "AC1: a map moved and changed in the same commit")]),
    ("M2 contents compared as sorted lines", I,
     [('gone[table.concat(m.minus, "\\n")] = true',
       'local l = table.clone(m.minus)\n\t\t\ttable.sort(l)\n\t\t\tgone[table.concat(l, "\\n")] = true'),
      ('if not gone[table.concat(m.plus, "\\n")] then',
       'local p = table.clone(m.plus)\n\t\t\ttable.sort(p)\n\t\t\tif not gone[table.concat(p, "\\n")] then')],
     [(RULE, "AC1: a map moved with only its lines reordered")]),
    ("M3 every add is a compaction", I, [('if not gone[table.concat(m.plus, "\\n")] then', "if true then")],
     [(RULE, "AC1: a map moved unchanged"), LISTS]),
    ("M4 a deletion is a compaction", I, [("elseif not m.deleted then", "else")],
     [(RULE, "AC1: a deleted map, or no map at all")]),
    ("M5 the first map names the compaction", I, [("return m.path", "return maps[1].path")],
     [(RULE, "AC1: beside a move of one map")]),
    ("M6 the log keeps rename detection", T, [('"--no-renames"', '"-M"')], [LISTS]),
    ("M7 the log keeps the AM filter", T, [('"--diff-filter=AMDT"', '"--diff-filter=AM"')], [LISTS]),
    ("M8 the patch reader never marks an add", I, [("m.added = true", "m.added = false")],
     [(RULE, "AC1: the map patch reader marks an added map"), LISTS, HISTORY]),
    ("M9 the patch reader reads the +++/--- headers as content", I,
     [('string.sub(line, 1, 4) ~= "+++ "', "true"), ('string.sub(line, 1, 4) ~= "--- "', "true")],
     [(RULE, "AC1: the map patch reader marks an added map"), LISTS, HISTORY]),
    ("M10 map diffs leak from one commit into the next", T, [("maps, cur = {}, nil", "cur = nil")], [LISTS]),
    ("M11 cuts ignores the repository it is given", T,
     [("git(trail.cutsArgs(head), dir)", "git(trail.cutsArgs(head))")], [LISTS]),
    ("M12 cuts ignores the head it is given", T,
     [("git(trail.cutsArgs(head), dir)", 'git(trail.cutsArgs("HEAD"), dir)')],
     [(CUTS, "AC2: trail.cuts reads the history of the head")]),
    ("M13 history inverts the shared rule", H, [("ids.cutFile(maps) ~= nil", "ids.cutFile(maps) == nil")],
     [HISTORY, PARITY]),
    ("M14 the trail header keeps the old sentence", T,
     [("Moving the map unchanged (c0114) is not a compaction; moving and changing it in the same commit is\n"
       "--   one (c0226: `cuts` judges by ids.cutFile, history's rule).",
       "Moving the map (c0114) is not a compaction.")], [(DOCS, "AC3: the trail module's header")]),
    ("M15 a change in place is no compaction", I,
     [("\t\telseif not m.deleted then\n\t\t\treturn m.path", "\t\telseif false then\n\t\t\treturn m.path")],
     [(RULE, "AC1: a map changed in place")]),
    ("M16 an add is never a compaction", I, [('if not gone[table.concat(m.plus, "\\n")] then', "if false then")],
     [(RULE, "AC1: a map added with no deletion")]),
    ("M17 history's comment keeps the old words", H,
     [("ids.cutFile: moving the map unchanged is none, moving and changing it in\n-- one commit is one)",
       "moving the map is none)")], [(DOCS, "AC3: history's header comment")]),
    ("M18 the lesson keeps the old words", L,
     [("(c0118 design review 001 F2), and a `git mv` that also changes the map's content is one: `trail.cuts` and "
       "history judge both by the one rule, `ids.cutFile`, over a log without renames (c0226: the `-M` log "
       "`trail.cuts` read before listed a moved and changed map as no compaction).",
       "(c0118 design review 001 F2; `trail.cuts` reads it with renames for the same reason).")],
     [(DOCS, "AC3: the lesson")]),
    ("M19 cuts compares blob ids (--raw)", T,
     [('return trail.parseCuts(git(trail.cutsArgs(head), dir) or "")', BLOB_CUTS)], [LISTS, PARITY]),
    ("M20 parseCuts judges by its own copy of the rule (every add beside a deletion is a move)", T,
     [("local file = ids.cutFile(maps)", OWN_RULE)], [LISTS, PARITY]),
    ("M21 the patch reader never marks a deletion", I, [("m.deleted = true", "m.deleted = false")],
     [(RULE, "AC1: the map patch reader marks a deleted map"), LISTS, HISTORY]),
    ("M22 a moved and changed map is named by the file it left", I,
     [(ADD_RETURN,
       'if not gone[table.concat(m.plus, "\\n")] then\n\t\t\t\tfor _, d in maps do\n\t\t\t\t\tif d.deleted then\n'
       '\t\t\t\t\t\treturn d.path\n\t\t\t\t\tend\n\t\t\t\tend\n\t\t\t\treturn m.path')],
     [(RULE, "AC1: a map moved and changed in the same commit")]),
]


def run(clone, *specs):
    r = subprocess.run(["lune", "run", "tests/run", "--", *specs], cwd=os.path.join(clone, "z-nile"),
                       capture_output=True, text=True, timeout=600)
    return r.returncode, r.stdout + r.stderr


def fails(out, spec, case):
    lines = out.splitlines()
    for i, line in enumerate(lines):
        if line.startswith(f"FAIL {spec} :: ") and (case is None or case in line):
            detail = lines[i + 1] if i + 1 < len(lines) else ""
            if "expected" in detail:
                return True, detail.strip()
    return False, ""


def main():
    tmp = tempfile.mkdtemp(prefix="c0226-mutants-")
    clone = os.path.join(tmp, "repo")
    ok = True
    try:
        subprocess.run(["git", "clone", "-q", "--no-hardlinks", "--no-checkout", TOP, clone], check=True)
        subprocess.run(["git", "-C", clone, "remote", "remove", "origin"], check=True)
        subprocess.run(["git", "-C", clone, "checkout", "-q", "--detach", BASE], check=True)
        subprocess.run(["git", "-C", clone, "apply", PATCH], check=True)
        dest = os.path.join(clone, "z-nile", DIR)
        os.makedirs(dest, exist_ok=True)
        for name in os.listdir(ACC):
            shutil.copy(os.path.join(ACC, name), dest)
        code, out = run(clone, RULE, CUTS, DOCS, HIST)
        print(f"unmutated: {'PASS' if code == 0 else 'FAIL'}: {out.strip().splitlines()[-1]}")
        ok = ok and code == 0
        for name, path, edits, wants in MUTANTS:
            full = os.path.join(clone, path)
            original = open(full).read()
            text = original
            for old, new in edits:
                if text.count(old) < 1:
                    print(f"{name}: SETUP ERROR: pattern not found: {old!r}")
                    ok = False
                    break
                text = text.replace(old, new)
            else:
                open(full, "w").write(text)
                assert open(full).read() != original  # read back: the edit applied
                specs = sorted({spec for spec, _ in wants})
                code, out = run(clone, *specs)
                results = []
                for spec, case in wants:
                    killed, detail = fails(out, spec, case)
                    results.append(killed)
                    where = f"{os.path.basename(spec)} :: {case or 'any case'}"
                    print(f"{name}: {'KILLED' if killed else 'SURVIVED'} ({where}) {detail[:140]}")
                ok = ok and all(results)
                open(full, "w").write(original)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("ALL KILLED" if ok else "NOT ALL KILLED")
    sys.exit(0 if ok else 1)


main()
