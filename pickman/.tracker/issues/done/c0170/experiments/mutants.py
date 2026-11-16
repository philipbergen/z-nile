# Mutation check for c0170. Usage: python3 -I mutants.py <clone> [ids...]
# <clone>: a separate clone under the temp folder at R0059's tip (69282043) with the move done
# (mkdir -p pickman/tests/helper/plain && git mv pickman/tests/unit/plain/plain.spec.luau pickman/tests/helper/plain/
# && rmdir pickman/tests/unit/plain),
# experiments/c0170.patch applied and this issue's acceptance/ copied in. Each mutant breaks the implementation; one of c0170's specs must fail on an
# assertion. Prints which cases failed.
import os, subprocess, sys, tempfile
clone = os.path.realpath(sys.argv[1])
tmp = os.path.realpath(tempfile.gettempdir())
def common(cwd):
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, cwd=cwd)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else ""
here, there = common(os.path.dirname(os.path.abspath(__file__))), common(clone) if os.path.isdir(clone) else ""
if not clone.startswith(tmp + os.sep) or not there or there == here:
    sys.exit(f"refused: {clone} is not a separate clone under {tmp}")
home = os.path.join(clone, "pickman")
SPECS = [".tracker/issues/c0170/acceptance/tiers.spec.luau", ".tracker/issues/c0170/acceptance/layout.spec.luau"]
T = os.path.join(home, "tests/meta/tiers.luau")
A = os.path.join(home, "tests/meta/architecture.spec.luau")
S = os.path.join(home, "skills/pickman-test/SKILL.md")
M = {
 "T1": (T, "local mine = helperOf(d) == helper or d == T or under(d, fixtures)", "local mine = helperOf(d) == helper or d == T or under(d, fixtures) or under(d, \"tests/lib/\")"),
 "T2": (T, "\tif not found then\n", "\tif false then\n"),
 "T3": (T, "if name and d ~= T then", "if false then"),
 "T4": (T, '"^tests/helper/([^/]+)/[^/]+%.spec%.luau$"', '"^tests/helper/([^/]+)/.+%.spec%.luau$"'),
 "T5": (T, "if not helpers[helper] then", "if false then"),
 "T6": (T, "\t\tif not mine then\n", "\t\tif not mine and #out == 0 then\n"),
 "T7": (A, "tiers.violations(g, helpers)", "tiers.violations({ files = (function() local o = {} for _, f in g.files do if string.match(f, \"^tests/helper/\") then table.insert(o, f) end end return o end)(), deps = g.deps }, helpers)"),
 "T8": (A, 't.expect(table.concat(tiers.violations(g, helpers), "\\n")).toBe("")', 'tiers.violations(g, helpers)'),
 "T9": (A, "tiers.violations(g, helpers)", "tiers.violations({ files = g.files, deps = {} }, helpers)"),
 "T10": (S, "| `tests/helper/<helper>/` |", "| `tests/helpers/<helper>/` |"),
 "T11": (T, "\tfor _, file in g.files do\n\t\tif string.match(file", "\tfor _, file in g.files do\n\t\tif #out > 0 then\n\t\t\tbreak\n\t\tend\n\t\tif string.match(file"),
 "T12": (A, "tiers.violations(g, helpers)", "tiers.violations({ files = g.files, deps = (function() local o = {} for f, ds in g.deps do local k = {} for _, d in ds do if string.match(d, \"^tests/lib/\") then table.insert(k, d) end end o[f] = k end return o end)() }, helpers)"),
 "T13": (T, "local mine = helperOf(d) == helper or", "local mine = string.sub(helperOf(d) or \"\", 1, #helper) == helper or"),
 "T14": (T, "or d == T or under(d, fixtures)", "or d == T or under(d, \"tests/fixtures/\")"),
 "R1": (T, "\t\tif helperOf(d) == helper then\n", "\t\tif helperOf(d) == helper or under(d, fixtures) then\n"),
 "R2": (T, "local fixtures = `tests/fixtures/{helper}/`", "local fixtures = `tests/fixtures/{helper}`"),
 "R3": (T, 'elseif under(file, "tests/unit/") then', 'elseif string.match(file, "^tests/unit/[^/]+/") then'),
 "R4": (T, "if name and d ~= T then", "if name and d ~= T and name ~= \"renamed\" then"),
 "R5": (A, "tiers.violations(g, helpers)", "tiers.violations({ files = g.files, deps = (function() local o = {} for f, ds in g.deps do local k = {} for _, d in ds do if not string.match(d, \"^tests/fixtures/\") then table.insert(k, d) end end o[f] = k end return o end)() }, helpers)"),
 "Q1": (T, "\tfor _, d in reached(g, file) do\n\t\tlocal name", "\tfor _, d in (g.deps[file] or {}) do\n\t\tlocal name"),
 "Q2": (T, "\tfor _, d in reached(g, file) do\n\t\tlocal mine", "\tfor _, d in direct do\n\t\tlocal mine"),
 "Q3": (T, 'if under(d, "tests/") and not under(d, "tests/lib/") then', 'if under(d, "tests/fixtures/") then'),
 # design review 004
 "V1": (T, 'elseif under(d, "../") then', "elseif false then"),
 "V2": (T, "\t\t\t\ttable.insert(out, d)\n", "\t\t\t\tif under(d, \"tests/lib/\") or under(d, \"../\") then\n\t\t\t\t\ttable.insert(out, d)\n\t\t\t\tend\n"),
 "V3": (T, ' or string.match(path, "^tests/lib/([^/]+)/")', ""),
 # design review 005
 "U1": (T, 'if string.lower(string.sub(d, 1, 6)) == "tests/" and not listed[d] then', "if false then"),
 "U2": (T, "if g.dynamic and table.find(g.dynamic, file) then", "if false then"),
 "Q4": (T, 'if under(d, "tests/") and not under(d, "tests/lib/") then', 'if not under(d, "tests/lib/") then'),
 "V4": (A, "elseif fs.isFile(`tests/lib/{name}/init.luau`) then", "elseif false then"),
}
def run():
    r = subprocess.run(["lune", "run", "tests/run", "--"] + SPECS, cwd=home, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr
code, out = run()
print("BASE", "pass" if code == 0 else "FAIL", out.strip().splitlines()[-1])
for mid in (sys.argv[2:] or list(M)):
    path, old, new = M[mid]
    text = open(path).read()
    assert text.count(old) == 1, (mid, "anchor not found once")
    open(path, "w").write(text.replace(old, new))
    try:
        code, out = run()
    finally:
        open(path, "w").write(text)
    fails = [l.split(":: ")[-1].strip() for l in out.splitlines() if l.startswith("FAIL")]
    bad = "not an assertion failure" in out
    print(mid, "ERROR" if bad else ("killed" if code != 0 else "SURVIVED"), "|", "; ".join(fails))
