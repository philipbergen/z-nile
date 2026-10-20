"""c0083 prep: mutation driver, run from the root of a throwaway clone that holds the prototype (never the real repository)."""
import subprocess, sys, re
# Refuse anything but a throwaway clone: it commits and resets --hard where it runs.
_top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
if subprocess.run(["git", "remote"], capture_output=True, text=True).stdout.strip() or "/.worktree/" in _top or "/tracker/" in _top:
    sys.exit("mutate.py: refusing: run it only in a throwaway clone with no remote, outside every real checkout")
SU="scripts/lib/suites.luau"; AF="scripts/affected.luau"; CK="scripts/check.sh"; ST="scripts/hooks/stop.sh"
TS=".claude/skills/testing/SKILL.md"; TR=".claude/skills/tracker/SKILL.md"; EX=".claude/skills/execute-raft/SKILL.md"; RV=".claude/skills/review/SKILL.md"
M = [
 ("M1 list drops both", SU, 'if side == name or side == "both" then', 'if side == name then', "spec"),
 ("M2 meta by the graph", SU, 'if string.match(spec, "^tests/meta/") then\n\t\treturn "both"', 'if false then\n\t\treturn "both"', "spec"),
 ("M3 list files tests/unit in harness too", SU, 'if side == name or side == "both" then', 'if side == name or side == "both" or (name == "harness" and string.match(f, "^tests/unit/") ~= nil) then', "spec"),
 ("M4 tests/scenario not a game folder", SU, '\t"^tests/scenario/",\n', '', "spec"),
 ("M4b contract/integration/runtime not game folders", SU, '\t"^tests/contract/",\n\t"^tests/integration/",\n', '', "spec"),
 ("M4c runtime not a game folder", SU, '\t"^tests/runtime/",\n', '', "spec"),
 ("M4d folders unanchored", SU, '\t"^tests/unit/",\n', '\t"tests/unit",\n', "spec"),
 ("M5 no f/d rule", SU, 'if string.match(spec, "^tests/acceptance/[fd]%d%d%d%d/") then\n\t\treturn "game"', 'if false then\n\t\treturn "game"', "spec"),
 ("M6 PLACE_LIB not counted", SU, 'if reach[graph.PLACE_LIB] then\n\t\treturn true\n\tend', '', "spec"),
 ("M7 rokit.toml not shared", SU, '\t"^rokit%.toml$",\n', '', "spec"),
 ("M8 scripts/check.sh not shared", SU, '\t"^scripts/check%.sh$",\n', '', "spec"),
 ("M8b fence.sh not shared", SU, '\t"^scripts/lib/fence%.sh$",\n', '', "spec"),
 ("M8c replace-file.pl not shared", SU, '\t"^scripts/lib/replace%-file%.pl$",\n', '', "spec"),
 ("M9 tests/meta not shared", SU, '\t"^tests/meta/",\n\t"^%.luaurc$",', '\t"^%.luaurc$",', "spec"),
 ("M9b runner closure not shared", SU, 'return graph.closure(g, RUNNER)[path] == true', 'return false', "spec"),
 ("M10 harness by graph only", SU, 'if anyMatch(changed, HARNESS) then', 'if false then', "spec"),
 ("M11 fixture.luau not harness", SU, '\t"^tests/lib/fixture%.luau$",\n', '', "spec"),
 ("M11b cachepaths not harness", SU, '\t"^tests/lib/cachepaths%.luau$",\n', '', "spec"),
 ("M11c stylua.toml not harness", SU, '\t"^stylua%.toml$",\n', '', "spec"),
 ("M12 ^tests/lib/ is harness", SU, '\t"^scripts/",\n', '\t"^scripts/",\n\t"^tests/lib/",\n', "spec"),
 ("M13 .claude/ not harness", SU, '\t"^%.claude/",\n', '', "spec"),
 ("M13b tracker/templates not harness", SU, '\t"^tracker/templates/",\n', '', "spec"),
 ("M14 lobby drops text hits", SU, 'for _, s in suites.textAffected(g, changed) do\n\t\tset[s] = true\n\tend\n\tlocal out', 'for _, s in suites.textAffected(g, changed) do\n\t\tif not table.find(changed, "lobby.project.json") then\n\t\t\tset[s] = true\n\t\tend\n\tend\n\tlocal out', "spec"),
 ("M15 a project file runs the harness suite too", SU, 'if anyMatch(changed, HARNESS) then', 'if anyMatch(changed, HARNESS) or anyMatch(changed, GAME) then', "spec"),
 ("M16 any src change is the whole game suite", SU, 'if anyMatch(changed, GAME) then', 'if anyMatch(changed, GAME) or anyMatch(changed, { "^src/" }) then', "spec"),
 ("M17 select is textAffected only", SU, 'for _, s in suites.deps(g, changed) do\n\t\tset[s] = true\n\tend\n\tif anyMatch', 'for _, s in suites.textAffected(g, changed) do\n\t\tset[s] = true\n\tend\n\tif anyMatch', "spec"),
 ("M18 select uses changed[1] only", SU, 'function suites.select(g: graph.Graph, changed: { string }): { string } | "ALL"\n', 'function suites.select(g: graph.Graph, changed: { string }): { string } | "ALL"\n\tchanged = { changed[1] }\n', "spec"),
 ("M18b mixed non-shared list is ALL", SU, 'function suites.select(g: graph.Graph, changed: { string }): { string } | "ALL"\n', 'function suites.select(g: graph.Graph, changed: { string }): { string } | "ALL"\n\tif #changed > 1 then\n\t\treturn "ALL"\n\tend\n', "spec"),
 ("M19 no text references", SU, 'if suites.isSpec(spec) and names(refsOf(spec), changed) then', 'if false then', "spec"),
 ("M20 only existing paths count", SU, 'if t == c or string.sub(c, 1, #t + 1) == t .. "/" then', 'if r.live and (t == c or string.sub(c, 1, #t + 1) == t .. "/") then', "spec"),
 ("M21 leading / kept", SU, 'while string.sub(t, 1, 1) == "/" do\n\t\t\t\tt = string.sub(t, 2)\n\t\t\tend', '', "spec"),
 ("M21b interpolation pieces ignored", SU, '\t\t\t\telseif d == "{" then\n\t\t\t\t\ttable.insert(raw, table.concat(piece))', '\t\t\t\telseif d == "{" then\n\t\t\t\t\tpiece = {}', "spec"),
 ("M21c code between braces counted", SU, "\t\t\t\t\tlocal depth = 1\n\t\t\t\t\tj += 1\n", "\t\t\t\t\tlocal depth = 1\n\t\t\t\t\tj += 1\n\t\t\t\t\tfor lit in string.gmatch(string.sub(s, j, (string.find(s, string.char(125), j, true) or n) - 1), string.char(34) .. '([^' .. string.char(34) .. ']*)' .. string.char(34)) do\n\t\t\t\t\t\ttable.insert(raw, lit)\n\t\t\t\t\tend\n", "spec"),
 ("M22 --suite with no name selects changes", AF, '\telseif a == "--suite" then\n\t\tmode = "suite"', '\telseif a == "--suite" and process.args[i + 1] then\n\t\tmode = "suite"', "spec"),
 ("M23 --deps on a shared path prints ALL", AF, 'emit(suites.deps(graph.build({ "src", "tests" }), explicit))', 'local r = suites.select(graph.build({ "src", "tests" }), explicit)\n\tif r == "ALL" then\n\t\tprint("ALL")\n\telse\n\t\temit(r :: { string })\n\tend', "spec"),
 ("M24 --deps expanded with the harness suite", AF, 'emit(suites.deps(graph.build({ "src", "tests" }), explicit))', 'local gg = graph.build({ "src", "tests" })\n\tlocal r = suites.deps(gg, explicit)\n\tfor _, s in suites.list(gg, "harness") do\n\t\ttable.insert(r, s)\n\tend\n\temit(r)', "spec"),
 ("M25 --deps by require only", SU, 'for _, s in suites.textAffected(g, changed) do\n\t\tset[s] = true\n\tend\n\tlocal out', 'local out', "spec"),
 ("M26 --which by selected specs", SU, '\telseif isShared(g, path) then\n\t\tadd(set, "both")', '\telseif true then\n\t\tlocal r = suites.select(g, { path })\n\t\tif r == "ALL" then\n\t\t\tadd(set, "both")\n\t\telse\n\t\t\tfor _, spec in r :: { string } do\n\t\t\t\tadd(set, suites.of(g, spec))\n\t\t\tend\n\t\tend\n\telseif isShared(g, path) then\n\t\tadd(set, "both")', "spec"),
 ("M27 backlog acceptance path by closure", SU, 'local id, file = string.match(path, "^tracker/issues/([fdc]%d%d%d%d)/acceptance/(.+)$")', 'local id, file = nil, nil', "spec"),
 ("M28 active/ prefix skips rule 1", SU, '\t\t\tid, file = string.match(path, "^tracker/issues/active/([fdc]%d%d%d%d)/acceptance/(.+)$")', '\t\t\tid, file = nil, nil', "spec"),
 ("M29 a chore acceptance spec is game", SU, '\t\t\tlocal as = `tests/acceptance/{id}/{file}`', '\t\t\tlocal as = `tests/acceptance/f{string.sub(id, 2)}/{file}`', "spec"),
 ("M29b missing active chore is game", SU, '\tlocal ok, src = pcall(fs.readFile, file)\n\tif not ok then\n\t\treturn reach\n\tend', '\tlocal ok, src = pcall(fs.readFile, file)\n\tif not ok then\n\t\treach[graph.PLACE_LIB] = true\n\t\treturn reach\n\tend', "spec"),
 ("M30 --which with no paths prints both", AF, '\tif #explicit == 0 then\n\t\tfail("--which needs paths")\n\tend', '\tif #explicit == 0 then\n\t\tprint("harness")\n\t\tprint("game")\n\t\treturn\n\tend', "spec"),
 ("M31 game-design.md is game only", SU, '\telseif\n\t\tmatches(path, GAME)\n', '\telseif\n\t\tpath == "tracker/game-design.md"\n\t\tor matches(path, GAME)\n', "spec"),
 ("M32 check.sh --suite validated late", CK, 'case "${2:-}" in harness|game) suite=$2 ;; *) echo "unknown suite: ${2:-} (harness or game)" >&2; exit 2 ;; esac\n      mode=suite; shift ;;', 'suite=${2:-}; mode=suite; shift ;;', "spec"),
 ("M33 check.sh --suite ignores the selection", CK, '  lune run tests/run -- $selection\nelse', '  lune run tests/run\nelse', "spec"),
 ("M34 hook without --no-renames", ST, 'git diff --name-only --no-renames HEAD', 'git diff --name-only HEAD', "spec"),
 ("M35 hook keeps the src/tests filter", ST, '| sort -u || true)', "| grep -E '^(src|tests)/' || true)", "spec"),
 ("M36 failing selector skips the gate", ST, 'if picked=$(lune run scripts/affected -- $changed 2>/dev/null); then\n  [[ -z $picked ]] && exit 0\nfi', 'picked=$(lune run scripts/affected -- $changed 2>/dev/null) || exit 0\n[[ -z $picked ]] && exit 0', "spec"),
 ("M37 hook gates without asking", ST, 'if picked=$(lune run scripts/affected -- $changed 2>/dev/null); then\n  [[ -z $picked ]] && exit 0\nfi', '', "spec"),
 ("N1 inside-folder rule removed", SU, 'if r.live and string.sub(t, 1, #c + 1) == c .. "/" then', 'if false then', "spec"),
 ("N2 inside-folder rule ignores existence", SU, 'if r.live and string.sub(t, 1, #c + 1) == c .. "/" then', 'if string.sub(t, 1, #c + 1) == c .. "/" then', "spec"),
 ("N3 unpromoted chore closure empty", SU, '\t\t\t\t\treturn closureOf(g, path)\n', '\t\t\t\t\treturn {}\n', "spec"),
 ("N4 hook asks the selector with no paths", ST, '[[ -z $changed ]] && exit 0\n', '', "spec"),
 ("N5 land default is the harness suite", "scripts/tracker/main.luau", 'override or "scripts/check.sh --affected"', 'override or "scripts/check.sh --suite harness"', "AC9"),
 ("N6 AGENTS.md left on a local full gate", "AGENTS.md", "after a local gate (`scripts/check.sh --affected`))", "after a local full gate)", "AC8"),
 ("N7 template comment pastes the plain selector", "tracker/templates/issue/doc.md", "Output of `lune run scripts/affected -- --deps <touched paths>`", "Output of `lune run scripts/affected -- <touched paths>`", "AC7"),
 ("N8 commands row without --which", ".claude/skills/testing/SKILL.md", "; `--which <files…>` the suites they belong to", "", "AC7"),
 ("N9 architecture skill without the GAME list", ".claude/skills/architecture/SKILL.md", ", the selector in `scripts/lib/graph.luau` and the `GAME` list in `scripts/lib/suites.luau` must", " and the selector in `scripts/lib/graph.luau` must", "AC7"),
 ("O1 item documents match tokens above the item folder", SU, '(string.sub(c, 1, #t + 1) == t .. "/" and (item == nil or #t >= #item))', '(string.sub(c, 1, #t + 1) == t .. "/")', "spec"),
 ("O2 no tree readers", SU, '\t"tests/acceptance/c0082/real-tree.spec.luau",\n\t"tests/tooling/repo-fence.spec.luau",\n', '', "spec"),
 ("O3 real-tree selected only by text", SU, '\t"tests/acceptance/c0082/real-tree.spec.luau",\n', '', "spec"),
 ("O4 tree readers only for check.sh", SU, 'if string.match(c, "^tracker/issues/") or string.match(c, "^tracker/rafts/") then', 'if string.match(c, "/check%.sh$") then', "spec"),
 ("O5 item rule for issues only", SU, 'for _, kind in { "issues", "rafts" } do', 'for _, kind in { "issues" } do', "spec"),
 ("O6 item rule skips done/", SU, 'for _, life in { "", "active/", "done/" } do', 'for _, life in { "", "active/" } do', "spec"),
 ("O7 suites paragraph without the readers list", ".claude/skills/testing/SKILL.md", ", plus `TRACKER_TREE_READERS` (the specs", ", plus the readers (the specs", "AC7"),
 ("P1 item documents match tokens above the item folder", SU, '(string.sub(c, 1, #t + 1) == t .. "/" and (item == nil or #t >= #item))', '(string.sub(c, 1, #t + 1) == t .. "/")', "spec"),
 ("P2 check.sh under the narrow rule", SU, '\t\t\t\tand not string.match(path, "/check%.sh$")\n', '', "spec"),
 ("P3 acceptance specs under the narrow rule", SU, '\t\t\t\tand not string.find(path, "/acceptance/", 1, true)\n', '', "spec"),
 ("P4 no real-tree reader", SU, '\t"tests/acceptance/c0082/real-tree.spec.luau",\n}', '}', "spec"),
 ("P5 readers only for a check.sh", SU, 'if string.match(c, "^tracker/issues/") or string.match(c, "^tracker/rafts/") then', 'if string.match(c, "/check%.sh$") then', "spec"),
 ("P6 item rule for issues only", SU, 'for _, kind in { "issues", "rafts" } do', 'for _, kind in { "issues" } do', "spec"),
 ("P7 item rule skips done/", SU, 'for _, life in { "", "active/", "done/" } do', 'for _, life in { "", "active/" } do', "spec"),
 ("P8 item rule skips the backlog", SU, 'for _, life in { "", "active/", "done/" } do', 'for _, life in { "active/", "done/" } do', "spec"),
 ("P9 suites paragraph without the readers list", ".claude/skills/testing/SKILL.md", ", plus `TRACKER_TREE_READERS` (the specs", ", plus the readers (the specs", "AC7"),
 ("Q1 every file in an item folder is a document", SU, 'if root and string.match(path, "%.md$") then', 'if root then', "spec"),
 ("Q2 only check.sh and acceptance/ are exempt", SU, 'if root and string.match(path, "%.md$") then', 'if root and not string.match(path, "/check%.sh$") and not string.find(path, "/acceptance/", 1, true) then', "spec"),
 ("Q3 the rule skips the issue backlog and done rafts", SU, 'if root and string.match(path, "%.md$") then', 'if root and string.match(path, "%.md$") and not (kind == "issues" and life == "") and not (kind == "rafts" and life == "done/") then', "spec"),
 ("Q4 the reader trigger fires only for tracker/issues", SU, 'if string.match(c, "^tracker/issues/") or string.match(c, "^tracker/rafts/") then', 'if string.match(c, "^tracker/issues/") then', "spec"),
 # docs and sequestered files: c0083's check.sh
 ("D1 Phase 5 left on --full", EX, 'rerun `scripts/check.sh --affected`', 'rerun `scripts/check.sh --full`', "AC8"),
 ("D2 Phase 0 without --which", EX, "`lune run scripts/affected -- --which <the raft's Touched modules>` prints", "the raft touches", "AC8"),
 ("D3 commands row ties --full to rafts", TS, "every spec, on demand. `scripts/setup.sh` and GitHub CI use it.", "every spec, on demand. Used by raft `check.sh` files and by CI", "AC8"),
 ("D4 old Graph-miss sentence kept", TS, "`tracker.sh done` does not need re-running for that fix commit.", "`tracker.sh done` does not need re-running for that fix commit. A spec fails under `--full` but wasn't selected for the same diff.", "AC8"),
 ("D5 Merging only says BLOCKED", TR, None, None, "AC8"),
 ("D6 Merging excepts template drift", TR, "This review is not one of those rounds.", "This review is not one of those rounds. A template-drift RC0 line is not BLOCKED.", "AC8"),
 ("D7 a second line in a raft check.sh", "tracker/rafts/R0035/check.sh", 'scripts/check.sh --affected\n', 'scripts/check.sh --affected\n# extra\n', "AC9"),
 ("D8 another done check.sh changes", "tracker/issues/done/c0001/check.sh", None, None, "AC9"),
 ("D9 R0039 left on --full", "tracker/rafts/R0039/check.sh", 'check "RC0: repo gate passes (the suites this raft touches)" scripts/check.sh --affected', 'check "RC0: repo gate passes (full)" scripts/check.sh --full', "AC9"),
 ("D10 RC0 replaced and a blank line deleted", "tracker/rafts/R0012/check.sh", None, None, "AC9"),
 ("D11 done argv stays --full", "scripts/tracker/main.luau", 'sh.stream("bash", { "scripts/check.sh", "--affected" })', 'sh.stream("bash", { "scripts/check.sh", "--full" })', "AC9"),
 ("D12 one args: --affected", "tests/acceptance/c0074/done-gate.spec.luau", 't.expect(has(seen, "args: --affected")).toBe(true)', 't.expect(has(seen, "args: --full")).toBe(true)', "AC9"),
 ("D13 a toBe(full) removed", "tests/acceptance/c0074/done-gate.spec.luau", None, None, "AC9"),
 ("D14 force one kept", TS, "- **Suites**:", "- **Full run**: scripts force one.\n- **Suites**:", "AC7"),
 ("D15 review item 4 without --deps", RV, "run `lune run scripts/affected -- --deps <path>`", "run `lune run scripts/affected -- <path>`", "AC7"),
 ("D16 c0080 grep changes two lines", "tracker/issues/done/c0080/check.sh", None, None, "AC9"),
]
base = subprocess.run(["git","rev-parse","HEAD"],capture_output=True,text=True).stdout.strip()
def special(mid, s):
    if mid.startswith("D5"):
        i = s.index("\n**Selector miss.**"); j = s.index("\n## The PR is the visible record")
        return s[:i] + "\n**Selector miss.** A selector miss is `BLOCKED:`.\n" + s[j:]
    if mid.startswith("D8"):
        return s + "# touched\n"
    if mid.startswith("D10"):
        assert "\n\n" in s
        return s.replace("\n\n", "\n", 1)
    if mid.startswith("D13"):
        return s.replace('toBe("full")', 'toBe("ful" .. "l")', 1)
    if mid.startswith("D16"):
        return s.replace("#!/usr/bin/env bash\n", "#!/usr/bin/env bash\n# touched\n", 1)
    raise Exception(mid)
only = sys.argv[1:] 
for mid, path, old, new, kind in M:
    if only and not any(mid.startswith(o + " ") for o in only): continue
    s = open(path).read()
    if old is None:
        t = special(mid, s)
    else:
        n = s.count(old)
        if n != 1:
            print(f"{mid}: NOT APPLIED (count {n})"); continue
        t = s.replace(old, new)
    open(path, "w").write(t)
    subprocess.run(["git","commit","-qam",mid])
    if kind == "spec":
        out = subprocess.run(["lune","run","tests/run","--","tracker/issues/c0083/acceptance/suites.spec.luau"],capture_output=True,text=True)
        o = out.stdout + out.stderr
        lines = o.splitlines()
        fails = []
        for k, l in enumerate(lines):
            m = re.match(r"\s*FAIL .*?:: (.*)$", l)
            if m:
                msg = lines[k+1].strip() if k+1 < len(lines) else ""
                msg = re.sub(r"^.*?suites\.spec:", "spec:", msg)
                fails.append(f"[{m.group(1)[:60]}] {msg[:110]}")
        load = "could not load" in o
        summ = [l for l in lines if "spec files" in l]
        print(f"{mid}: {'LOAD ERROR ' if load else ''}{summ[-1] if summ else '?'}")
        for f in fails[:3]: print("     ", f)
        if not fails: print("      SURVIVED" if not load else "")
    else:
        out = subprocess.run(["bash","tracker/issues/c0083/check.sh"],capture_output=True,text=True)
        o = out.stdout + out.stderr
        lines = o.splitlines()
        hit = [ (l, lines[k+1].strip() if k+1 < len(lines) else "") for k,l in enumerate(lines) if l.startswith("FAIL  " + kind)]
        others = [l[6:10] for l in lines if l.startswith("FAIL  ") and not l.startswith("FAIL  " + kind)]
        print(f"{mid}: {kind} {'FAILED' if hit else 'SURVIVED'}" + (f" ({hit[0][1][:120]})" if hit else "") + (f" other fails: {others}" if others else ""))
    subprocess.run(["git","reset","-q","--hard",base])
