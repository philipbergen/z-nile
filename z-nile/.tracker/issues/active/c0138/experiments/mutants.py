#!/usr/bin/env python3
"""c0138 mutation check: applies each mutant to z-nile/engine/trail.luau or ids.luau, runs the c0138 specs
(renamed.spec and kept.spec) and reports which mutants the specs kill. Each mutant must die on an assertion.

Run from the repository root:  python3 "$(./zn find c0138)/experiments/mutants.py" [M1 M7 ...]   (no argument: every\nmutant; about 8 minutes: give it a bound of 900 s or more). It finds the specs from its own place, so it runs from\nthe backlog, from active/ and, after done, from the promoted folder.

It never touches git. It saves the two engine files first, restores them after every mutant and at exit, and refuses
(exit 2) when a mutant's edit does not apply to the file as it is: a base whose text moved fails loudly instead of
skipping a mutant. Every spec run is bounded (CPU limit and wall clock) and its process group is killed on timeout.
Commit nothing while it runs; run it on a clean tree of the engine files.
"""
import os, signal, subprocess, sys, tempfile

TOP = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, cwd=os.path.dirname(os.path.abspath(__file__))).stdout.strip()
HOME = os.path.join(TOP, "z-nile")
E = os.path.join(HOME, "engine") + "/"
PATHS = {"trail": E + "trail.luau", "ids": E + "ids.luau"}
HERE_ACC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "acceptance")
PROMOTED = os.path.join(HOME, "tests/acceptance/c0138")
ACC = HERE_ACC if os.path.isdir(HERE_ACC) else PROMOTED  # found from this file's own place: `ready` moves the folder
SPECS = [os.path.join(ACC, "renamed.spec.luau"), os.path.join(ACC, "kept.spec.luau")]
SECONDS = 240

GOOD = {k: open(p).read() for k, p in PATHS.items()}
BACKUP = tempfile.mkdtemp(prefix="c0138-mutants-")
for k, text in GOOD.items():
    open(os.path.join(BACKUP, k + ".luau"), "w").write(text)
print("good copies of the engine files:", BACKUP, flush=True)

M={
 "M1 old rule: every cut with a doc resets": ("trail","return c.doc and cutsId(c.sha)","return c.doc and cuts[c.sha] ~= nil"),
 "M2 old side not named": ("ids","			out[old] = true\n",""),
 "M3 new side not named": ("ids","			out[new] = true\n",""),
 "M4 pair whose sides agree counts": ("ids","		if old ~= new then","		if true then"),
 "M5 unparseable map names nothing": ("trail","		if not map then\n			return nil\n		end\n		for id in","		if not map then\n			continue\n		end\n		for id in"),
 "M6 parent's map read": ("trail","git({ \"show\", `{sha}:{file}` })","git({ \"show\", `{sha}^:{file}` })"),
 "M6b parent's commit listed": ("trail","		sha,\n		\"--\",\n","		sha .. \"^\",\n		\"--\",\n"),
 "M7 added diff lines only": ("trail","""		local text = git({ "show", `{sha}:{file}` })
		if not text then""","""		local d = git({ "diff", "--unified=0", `{sha}^`, sha, "--", file })
		local text = nil
		if d then
			local keep: { string } = {}
			for line in string.gmatch(d, "[^\\n]+") do
				if string.sub(line, 1, 1) == "+" and string.sub(line, 1, 3) ~= "+++" then
					table.insert(keep, string.sub(line, 2))
				end
			end
			text = table.concat(keep, "\\n")
		end
		if not text then"""),
 "M8 unreadable does not reset": ("trail","return renamed == nil or renamed[id] == true","return renamed ~= nil and renamed[id] == true"),
 "M9 a commit with no map change names nothing": ("trail","	if #maps == 0 then\n		return nil\n	end\n","	if #maps == 0 then\n		return {}\n	end\n"),
 "M9b a failed listing names nothing": ("trail","	if not listed then\n		return nil\n	end\n","	if not listed then\n		return {}\n	end\n"),
 "M9c a failed show names nothing": ("trail","		if not text then\n			return nil\n		end\n		table.insert(maps","		if not text then\n			continue\n		end\n		table.insert(maps"),
 "M10 only the retired map listed": ("trail","	for _, f in ids.MAP_FILES do\n		table.insert(args, f)\n	end\n	local listed","	table.insert(args, ids.MAP_FILES[2])\n	local listed"),
 "M10b only the current map listed": ("trail","	for _, f in ids.MAP_FILES do\n		table.insert(args, f)\n	end\n	local listed","	table.insert(args, ids.MAP_FILES[1])\n	local listed"),
 "M12 a non-cut commit resets": ("trail","		if not cuts[sha] then\n			return false\n		end","		if not cuts[sha] then\n			return true\n		end"),
 "M14 the parent commit's map is read too": ("trail","		table.insert(maps, text)\n","		table.insert(maps, text)\n		local prev = git({ \"show\", `{sha}^:{file}` })\n		if prev then\n			table.insert(maps, prev)\n		end\n"),
 "M15 the memo has one slot, not one per commit": ("trail","		local seen = renamed[sha]\n		if not seen then\n			seen = { names = trail.renames(sha) }\n			renamed[sha] = seen","		local seen = renamed[\"k\"]\n		if not seen then\n			seen = { names = trail.renames(sha) }\n			renamed[\"k\"] = seen"),
 "M16 the note marks only a renamed start": ("trail","	if start and cuts[start.sha] then","	if start and cuts[start.sha] and cutsId(start.sha) then"),
 "M14b the parent's map is read too when it parses": ("trail","		table.insert(maps, text)\n","		table.insert(maps, text)\n		local prev = git({ \"show\", `{sha}^:{file}` })\n		if prev and ids.parseMap(prev) then\n			table.insert(maps, prev)\n		end\n"),
 "MA only the first map file is read": ("trail","		table.insert(maps, text)\n","		table.insert(maps, text)\n		break\n"),
 "MB only the last map file is read": ("trail","		table.insert(maps, text)\n","		maps = { text }\n"),
 "MC the last map decides a parse failure": ("trail",[("	local out: { [string]: boolean } = {}\n	for _, text in maps do","	local bad = false\n	local out: { [string]: boolean } = {}\n	for _, text in maps do"),("		if not map then\n			return nil\n		end\n		for id in","		bad = map == nil\n		if not map then\n			continue\n		end\n		for id in"),("	return out\nend\n\n-- Whether","	if bad then\n		return nil\n	end\n	return out\nend\n\n-- Whether")],None),
 "MF a map file that does not parse is skipped before the join": ("trail","		table.insert(maps, text)\n","		if ids.parseMap(text) then\n			table.insert(maps, text)\n		end\n"),
 "ME no added-or-modified filter": ("trail","		\"--diff-filter=AM\",\n",""),
 "M17 a commit that touched only a review file counts as a document change": ("trail","return c.doc and cutsId(c.sha)","return cutsId(c.sha)"),
 "M13 every map file present is read, changed or not": ("trail","	local listed = git(args)\n","	local listed = git({ \"ls-tree\", \"--name-only\", sha, \"--\", ids.MAP_FILES[1], ids.MAP_FILES[2] })\n"),
}


def restore():
    for k, p in PATHS.items():
        open(p, "w").write(GOOD[k])


CHILD = None


def on_signal(signum, _frame):
    restore()  # a bound's SIGTERM or a Ctrl-C must not leave a mutant in the engine
    if CHILD is not None:
        try:
            os.killpg(CHILD.pid, signal.SIGKILL)  # nor a spec run going
        except OSError:
            pass
    sys.exit(128 + signum)


signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)


def run_specs():
    cmd = "ulimit -t %d; exec lune run tests/run -- %s" % (SECONDS, " ".join(SPECS))
    global CHILD
    p = CHILD = subprocess.Popen(["/bin/sh", "-c", cmd], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=SECONDS + 30)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        out, _ = p.communicate()
        out += "\nTIMEOUT"
    return out


only = sys.argv[1:]
unknown = [n for n in only if n not in [name.split(" ")[0] for name in M]]
if unknown:
    print("NO SUCH MUTANT:", ", ".join(unknown))
    sys.exit(2)
bad = []
wrecked = []
for name, (k, a, b) in M.items():
    if only and name.split(" ")[0] not in only:
        continue
    pairs = a if isinstance(a, list) else [(a, b)]
    if any(x not in GOOD[k] for x, _ in pairs):
        restore()
        print("NOT APPLIED:", name, "(the edit's text is not in", PATHS[k] + ")")
        sys.exit(2)
text = None
try:
    for name, (k, a, b) in M.items():
        if only and name.split(" ")[0] not in only:
            continue
        pairs = a if isinstance(a, list) else [(a, b)]
        restore()
        text = GOOD[k]
        for x, y in pairs:
            text = text.replace(x, y, 1)
        open(PATHS[k], "w").write(text)
        out = run_specs()
        lines = out.splitlines()
        # an assertion failure prints `FAIL <file> :: <case>`; a spec that could not load prints `FAIL <file>: <error>`
        fails = [l for l in lines if l.startswith("FAIL") and " :: " in l]
        broken = [l for l in lines if l.startswith("FAIL") and " :: " not in l]
        summ = [l for l in lines if "passed," in l]
        print(name, "=>", summ[-1] if summ else out[-200:])
        for l in fails:
            print("    ", l[:150])
        for l in broken:
            print("     BROKEN:", l[:200])
        if broken or not summ or "TIMEOUT" in out:
            wrecked.append(name)
        elif not fails:
            bad.append(name)
finally:
    restore()
print("saved copies:", BACKUP)
if wrecked:
    print("BROKEN (not killed on an assertion; the edit broke the build, or the run crashed or timed out):", ", ".join(wrecked))
    sys.exit(2)
if bad:
    print("SURVIVED:", ", ".join(bad))
    sys.exit(1)
print("all mutants killed")
