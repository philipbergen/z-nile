# Mutation check for c0185. Usage: python3 -I mutants.py <clone> [ids...]
# <clone>: a separate clone under the temp folder (refused otherwise) at origin/main with c0184 delivered (its tree, or the
# prototype this issue was designed on: main 1a88c247 + c0184's prep tip 642400ce applied as its Implementation steps say),
# experiments/c0185.patch applied after the move (`git mv pickman/tests/lib/place.luau z-nile/tests/lib/place.luau`), and
# this issue's acceptance/ and experiments/ copied to z-nile/.tracker/issues/c0185/. Each mutant breaks the implementation; the
# row's spec (or the AC6 fixture, whose function is extracted from the issue's check.sh) must fail on an assertion. Prints killed or SURVIVED per id. Ids are the Rules and mutants rows'.
import os, subprocess, sys, tempfile
clone = os.path.realpath(sys.argv[1])
tmp = os.path.realpath(tempfile.gettempdir())
def common(cwd):
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, cwd=cwd)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else ""
here, there = common(os.path.dirname(os.path.abspath(__file__))), common(clone) if os.path.isdir(clone) else ""
if not (clone.startswith(tmp + os.sep) or "/scratchpad/" in clone) or not there or there == here:
    sys.exit(f"refused: {clone} is not a separate clone under {tmp}")
Z = os.path.join(clone, "z-nile")
ACC = ".tracker/issues/c0185/acceptance/"
G, GS = "z-nile/lib/graph.luau", ACC + "graph.spec.luau"
SEL, PS, CS, LS = ACC + "selector.spec.luau", ACC + "place.spec.luau", ACC + "crosshome.spec.luau", ACC + "library.spec.luau"
AFF, PL, CH, HO = "z-nile/affected.luau", "z-nile/tests/lib/place.luau", "z-nile/tests/lib/crosshome.luau", "z-nile/tests/lib/home.luau"
ARCH = "pickman/tests/meta/architecture.spec.luau"
M = {
 # graph.srcAliasAllowed, serverFile, srcAliasViolations
 "G1": (G, 'or (fromServer == true and string.sub(spec, 1, 20) == "@game/ServerStorage/")', 'or string.sub(spec, 1, 20) == "@game/ServerStorage/"', [GS]),
 "G2": (G, 'string.sub(spec, 1, 20) == "@game/ServerStorage/")', 'string.sub(spec, 1, 12) == "@game/Server")', [GS]),
 "G3": (G, "if best == nil or #root.path > #(best :: GameRoot).path then", "if best == nil then", [GS]),
 "G4": (G, "local server = graph.serverFile(file, places)", "local server = true", [GS]),
 # graph.placeInputs, affectedSpecs
 "G5": (G, 'if string.match(name, "%.project%.json$") and fs.isFile(`{dir}/{name}`) then', 'if name == "default.project.json" and fs.isFile(`{dir}/{name}`) then', [GS]),
 "G6": (G, '\t\t\ttable.insert(out, if string.sub(m.path, 1, 1) == "/" then m.path else normalize(home .. m.path))', '\t\t\tif string.sub(m.path, 1, 3) ~= "../" then\n\t\t\t\ttable.insert(out, normalize(home .. m.path))\n\t\t\tend', [GS, SEL]),
 "G6b": (G, '\t\t\ttable.insert(out, if string.sub(m.path, 1, 1) == "/" then m.path else normalize(home .. m.path))', '\t\t\ttable.insert(out, home .. m.path)', [GS]),
 "G7": (G, 'local ok, project = pcall(serde.decode, "json" :: "json", fs.readFile(`{dir}/{name}`))\n\t\tif not ok or type(project) ~= "table" or type((project :: any).tree) ~= "table" then', 'local ok, project = pcall(serde.decode, "json" :: "json", fs.readFile(`{dir}/{name}`))\n\t\tif false then', [GS]),
 "M6": (G, 'local ok, project = pcall(serde.decode, "json" :: "json", fs.readFile(`{dir}/{name}`))\n\t\tif not ok or type(project) ~= "table" or type((project :: any).tree) ~= "table" then', 'local ok, project = pcall(serde.decode, "json" :: "json", fs.readFile(`{dir}/{name}`))\n\t\tif false then', ["AC6"]),
 "Z1": (G, 'if string.sub(path, 1, 1) == "/" then\n\t\treturn false\n\tend\n\tlocal depth = 0', "local depth = 0", [GS]),
 "G8": (G, 'return { home .. "src", home .. "default.project.json", home .. "lobby.project.json" }', "return {}", [GS]),
 "G9": (G, "\t\t\tlocal list = inputs(home)\n\t\t\tfor _, f in changed do", "\t\t\tlocal list = { home .. \"src\", home .. \"default.project.json\", home .. \"lobby.project.json\" }\n\t\t\tfor _, f in changed do", [GS]),
 "G10": (G, "\t\t\tlocal list = inputs(home)\n\t\t\tfor _, f in changed do", "\t\t\tlocal list = inputs(home)\n\t\t\ttable.insert(list, home .. \"src\")\n\t\t\tfor _, f in changed do", [GS]),
 "G11": (G, "local inputs = inputsOf or graph.placeInputs", "local inputs = graph.placeInputs", [GS]),
 # affected.luau
 "A1": (AFF, '"[^/]*%.project%.json$",', '"default%.project%.json$",', [SEL]),
 "A2": (AFF, '"[^/]*%.project%.json$",', '".*%.project%.json$",', [SEL]),
 # the harness
 "P1": (PL, "if graph.insideFolder(root.path) then", "if true then", [PS]),
 "P2": (PL, "\t\tfor _, root in graph.gameRoots(decoded) do\n\t\t\tif graph.insideFolder(root.path) then\n\t\t\t\ttable.insert(roots, root.instance)\n\t\t\tend\n\t\tend", "\t\troots = { \"ReplicatedStorage/Shared\", \"ServerScriptService/Server\", \"StarterPlayer/StarterPlayerScripts/Client\", \"ServerScriptService/Lobby\" }", [PS]),
 "P3": (PL, "\t\terror(\n\t\t\t\"place.scripts: the place was not loaded by place.load, so its project file's script roots are unknown\",\n\t\t\t0\n\t\t)", "\t\treturn {}", [PS]),
 # crosshome
 "C1": (CH, 'if string.sub(file, 1, #logic + 1) == logic .. "/" then', "if true then", [CS]),
 "C2": (CH, 'if string.sub(dep, 1, 3) == "../" then', 'if string.sub(dep, 1, 10) == "../arcade/" then', [CS]),
 "C3": (CH, "if file ~= wrapper and table.find(deps[file], shared) ~= nil then", "if table.find(deps[file], shared) ~= nil then", [CS]),
 "C4": (CH, "if file ~= wrapper and table.find(deps[file], shared) ~= nil then", "local hit = false\n\t\tfor _, d in deps[file] do\n\t\t\thit = hit or string.find(d, \"tests/lib/place\", 1, true) ~= nil\n\t\tend\n\t\tif file ~= wrapper and hit then", [CS]),
 # the home rule
 "H1": (HO, "\t\t\t\tarcade = `../{LIBRARY_SHARED}`,\n", "", [LS]),
 "H2": (HO, 'if mapped["default.project.json"] and not found then', "if false then", [LS]),
 "H3": (HO, "if not graph.insideFolder(path) and libraryNode[target] then", 'if not graph.insideFolder(path) and string.sub(target, 1, 7) == "arcade/" then', [LS]),
 "H4": (HO, "if not graph.insideFolder(path) and libraryNode[target] then", "if not graph.insideFolder(path) then", [LS]),
 "H5": (HO, "elseif not physicallyInside(`{top}/{LIBRARY_HOME}`, `{top}/{h}/{path}`) then", "elseif false then", [LS]),
 "H6": (HO, '\t\twrapper(h, "tests/lib/place.luau", { "--!strict", `return {R}("../../../z-nile/tests/lib/place")` })', "", [LS]),
 # review 001: the walker, the nodes, the boundaries
 "N1": (HO, "if m.instance ~= libraryNode[target] then", "if false then", [LS]),
 "N2": (G, 'if type(path) == "table" and type((path :: any).optional) == "string" then\n\t\tpath = (path :: any).optional\n\tend', "", [GS, LS]),
 "N3": (HO, "elseif fs.isFile(`{top}/{h}/{path}/default.project.json`) then", "elseif false then", [LS]),
 "N5": (HO, "found = found or (m.instance == node and resolveIn(h, m.path) == target)", "found = found or (m.instance == node and string.sub(m.path, 1, 3) == \"../\")", [LS]),
 "X1": (G, "if f == p or string.sub(f, 1, #p + 1) == p .. \"/\" then", "if f == p or string.sub(f, 1, #p) == p then", [GS]),
 "X2": (PL, "\t\t\ttable.insert(found, node)\n", "", [PS]),
 "X3": (PL, "if d:IsA(\"LuaSourceContainer\") and not seen[d] then", "if d:IsA(\"LuaSourceContainer\") then", [PS]),
 "X5": (G, 'if\n\t\t\t\tinst == "ServerScriptService"\n\t\t\t\tor inst == "ServerStorage"\n\t\t\t\tor string.sub(inst, 1, 20) == "ServerScriptService/"\n\t\t\t\tor string.sub(inst, 1, 14) == "ServerStorage/"\n\t\t\tthen', 'if string.find(inst, "Server", 1, true) ~= nil then', [GS]),
 "X6": (G, "\tlocal depth = 0\n\tfor seg in string.gmatch(path, \"[^/]+\") do\n\t\tif seg == \"..\" then\n\t\t\tdepth -= 1\n\t\t\tif depth < 0 then\n\t\t\t\treturn false\n\t\t\tend\n\t\telseif seg ~= \".\" then\n\t\t\tdepth += 1\n\t\tend\n\tend\n\treturn true", "\treturn string.sub(path, 1, 3) ~= \"../\"", [GS]),
 # review 002
 "G12": (G, "return owners > 0 and servers == owners", "return servers > 0", [GS]),
 "M5": (G, "return owners > 0 and servers == owners", "return servers > 0", ["AC6"]),
 "Y1": ("z-nile/tests/lib/placespec.luau", "if place.resolveRequire(s, spec) == nil then", "if false then", [PS]),
 "Y2": ("z-nile/tests/lib/placespec.luau", 'for _, service in { "ReplicatedStorage", "ServerStorage" } do', 'for _, service in { "ReplicatedStorage" } do', [PS]),
 "Y4": (HO, 'local defaults: { graph.GameRoot } = mapped["default.project.json"] or {}', 'local defaults: { graph.GameRoot } = {}\n\t\t\tfor _, list in mapped do\n\t\t\t\tfor _, m in list do\n\t\t\t\t\ttable.insert(defaults, m)\n\t\t\t\tend\n\t\t\tend', [LS]),
 "Y9": (G, 'if file == root.path or string.sub(file, 1, #root.path + 1) == root.path .. "/" then\n\t\t\t\tif best == nil', 'if string.sub(file, 1, #root.path + 1) == root.path .. "/" then\n\t\t\t\tif best == nil', [GS]),
 "Y19": (CH, "if file ~= wrapper and table.find(deps[file], shared) ~= nil then", 'if string.sub(file, 1, 10) ~= "tests/lib/" and table.find(deps[file], shared) ~= nil then', [CS]),
 "M4": (G, "places = places or currentPlaces()", "places = places or { graph.gameRoots() }", ["AC6"]),
 # review 004
 "V2": (G, '\t\t\ttable.insert(out, if string.sub(m.path, 1, 1) == "/" then m.path else normalize(home .. m.path))', '\t\t\ttable.insert(out, normalize(home .. m.path))', [GS]),
 "V14": (PL, "if graph.insideFolder(root.path) then", 'if string.sub(root.path, 1, 3) ~= "../" then', [PS]),
 "V15": (HO, 'return if string.sub(path, 1, 1) == "/" then path else collapse(`{h}/{path}`)', "return collapse(`{h}/{path}`)", [LS]),
 # pickman's structural spec, run from a fixture home (AC6)
 "M1": (ARCH, "crosshome.logicOutside(g.deps, LOGIC)", "{}", ["AC6"]),
 "M2": (ARCH, "crosshome.placeBypass(g.deps, shared, wrapper)", "{}", ["AC6"]),
 "M3": (G, "local server = graph.serverFile(file, places)", "local server = true", ["AC6"]),
}
def run(specs):
    if specs == ["AC6"]:
        lines = open(os.path.join(Z, ACC[:-11], "check.sh")).read().split("\n")
        a = next(i for i, l in enumerate(lines) if l.startswith("ac6_fixture() {"))
        b = next(i for i, l in enumerate(lines) if l.startswith("ac6() {"))
        r = subprocess.run(["bash", "-c", f'export ZN_ROOT="{clone}"; ' + "\n".join(lines[a:b]) + "\nac6_fixture"], cwd=Z, capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr
    r = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=Z, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr
code, out = run([GS, SEL, PS, CS, LS])
print("BASE", "pass" if code == 0 else "FAIL", out.strip().splitlines()[-1])
code, out = run(["AC6"])
print("BASE AC6", "pass" if code == 0 else "FAIL")
for mid in (sys.argv[2:] or list(M)):
    rel, old, new, specs = M[mid]
    path = os.path.join(clone, rel)
    text = open(path).read()
    assert text.count(old) == 1, (mid, "anchor not found once")
    open(path, "w").write(text.replace(old, new))
    try:
        code, out = run(specs)
    finally:
        open(path, "w").write(text)
    fails = [l.split(":: ")[-1].strip()[:70] for l in out.splitlines() if l.strip().startswith("FAIL")] or ([l[:90] for l in out.splitlines() if l.startswith(("an outside", "a place", "a client", "the clean"))][:1] if specs == ["AC6"] else [])
    bad = "not an assertion failure" in out or "could not load spec" in out or "TypeError" in out
    print(mid, "ERROR" if bad else ("killed" if code != 0 else "SURVIVED"), "|", "; ".join(fails))
