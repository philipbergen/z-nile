# Mutation check for c0380. Usage: python3 -I mutants.py <clone> <a|b> [ids...]
# <clone> is a separate clone under the temp folder of a prototype commit (E2): `a` is origin/main with c0156's test
# parts, f0145's deps.patch and prototype.patch, f0145 done (specs promoted) and experiments/prototype.patch; `b` is
# the same plus f0186's prototype.patch. Never run it on a checkout of the repository: it refuses one.
# N rows weaken a narrowed spec (or a check.sh); acceptance/narrowed.spec must fail on an assertion.
# C rows are code mutants; the narrowed spec named must still fail on an assertion (what the narrowing keeps).
# W rows are the window's gaps (c0380 done, f0186 not yet): they must SURVIVE the narrowed spec, and the spec named
# after them (or none) is where they are caught.
# Prints, per mutant, killed or SURVIVED and the cases that failed.
import os, subprocess, sys, tempfile

clone, base = os.path.realpath(sys.argv[1]), sys.argv[2]
tmp = os.path.realpath(tempfile.gettempdir())


def common(cwd):
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                       capture_output=True, text=True, cwd=cwd)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else ""


here = common(os.path.dirname(os.path.abspath(__file__)))
there = common(clone) if os.path.isdir(clone) else ""
if not clone.startswith(tmp + os.sep) or not there or there == here or base not in ("a", "b"):
    sys.exit(f"refused: {clone} is not a separate clone under {tmp}, or the base is not a or b")
home = os.path.join(clone, "pickman")
NARROWED = ".tracker/issues/c0380/acceptance/narrowed.spec.luau"
A = lambda p: f"tests/acceptance/{p}.spec.luau"
LOBBY = "src/shared/Logic/Lobby/init.luau"
ROW_A = "table.insert(out, `{mark}{r.rank} {r.name} {r.score} {r.level}{Lobby.livesText(r.lives)}`)"
ROW_B = "table.insert(out, `{mark}{r.rank} {r.name} {r.score} {r.level} {Lobby.revivesText(r.revives)}`)"
ROW = ROW_A if base == "a" else ROW_B
BEST = '`YOUR BEST {string.format("%d", score)} {string.format("%d", level)}'

# id: (bases, file, old, new, spec that must fail (or survive, for W), the case expected among the failures)
M = {
    # the narrowed files and their checks
    "N1": ("ab", A("d0124/lobby"), '\t\tt.expect(L.bestLine({ score = 50, level = 2 }, "week")).toBe(nil)\n', "",
           NARROWED, "d0124/lobby.spec.luau is exactly"),
    "N2": ("ab", A("f0026/lobby"), "(line == w or string.sub(line, 1, #w + 1) == w .. \" \")",
           "string.sub(line, 1, #w) == w", NARROWED, "f0026/lobby.spec.luau is exactly"),
    "N3": ("ab", A("d0124/lobby"),
           "-- the best line ends as the row of the same score and level ends (nothing, or f0186's revives)\n\t\t",
           "-- the best line ends as the row of the same score and level ends (nothing, or f0186's revives) ",
           NARROWED, "d0124/lobby.spec.luau is exactly"),
    "N4": ("ab", A("f0145/views"), "\t\t\tt.expect(buy ~= \"\").toBe(true)\n\t\t\tfor", "\t\t\tdo return end\n\t\t\tfor",
           NARROWED, "f0145/views.spec.luau is exactly"),
    "N5": ("ab", A("c0128/golden"), "edfd74c3cd76d3eccd827af745ee6e671262c6f607232fef5a02713b4ef63074",
           "744eeb0f1d525ee47f52c01dd8cab3c4bcd511fd2edf28919f894712f64cbfc6", NARROWED, "nothing f0186 removes"),
    "N6": ("ab", ".tracker/issues/done/f0026/check.sh", 'check "AC5:', '# check "AC5:', NARROWED, "still run them"),
    "N7": ("ab", A("f0145/place"), '\t\t\t\t"three new lives",\n', "", NARROWED, "f0145/place.spec.luau is exactly"),
    "N8": ("ab", A("f0026/endtoend"), '\t\t\t\t"> 1 Ada 50 2"\n', '\t\t\t\t"> 1 Ada"\n', NARROWED,
           "f0026/endtoend.spec.luau is exactly"),
    # what each narrowed case still pins
    "C1": ("ab", LOBBY, 'then "> " else ""', 'then "" else ""', A("f0026/lobby"), "the highlight is a rank"),
    "C2": ("ab", LOBBY, ROW, ROW.replace("{r.score} {r.level}", "{r.level} {r.score}"), A("d0124/lobby"),
           "the list text is the panel's lines"),
    "C3": ("ab", LOBBY, '\treturn table.concat(out, "\\n")\n', '\treturn table.concat(out, " ")\n',
           A("f0026/lobby"), "the highlight is a rank"),
    "C4": ("ab", LOBBY, ROW, ROW.replace("{r.level}", "{r.level}0", 1), A("f0026/endtoend"),
           "the same run submits once"),
    "C5": ("ab", LOBBY, BEST, '`YOUR BEST {string.format("%d", score)}', A("d0124/lobby"),
           "the best line starts with the score and the level"),
    "C6": ("ab", LOBBY, 'if id ~= "all" or type(best) ~= "table" then', 'if type(best) ~= "table" then',
           A("d0124/lobby"), "the best line starts with the score and the level"),
    "C7": ("ab", LOBBY, "\treturn `{body}\\n{line}`\n", "\treturn `{line}\\n{body}`\n", A("d0124/lobby"),
           "the list text is the panel's lines"),
    "C8": ("ab", LOBBY, BEST, BEST + " X", A("d0124/lobby"), "the list text is the panel's lines"),
    "C9": ("ab", "src/lobby/client/LobbyView.luau", "Lobby.text(drawn, highlight, best, shown)",
           "Lobby.text(drawn, highlight, nil, shown)", A("d0124/adapters"), "LobbyView adds the best line"),
    "C10": ("ab", "src/lobby/client/LobbyView.luau", "Lobby.text(drawn, highlight, best, shown)",
            "Lobby.text(drawn, nil, best, shown)", A("f0026/adapters"), "the lobby screen asks for all once"),
    "C11": ("ab", LOBBY, '\tif mode ~= "live" and mode ~= "closed" then\n\t\tline ..= " (TEST: NOTHING IS CHARGED)"',
            '\tif mode ~= "closed" then\n\t\tline ..= " (TEST: NOTHING IS CHARGED)"', A("f0145/views"),
            "the lobby's line: free, else what is held"),
    "C12": ("ab", LOBBY, "{math.ceil((at - now) / 60)} MIN", "{math.floor((at - now) / 60)} MIN", A("f0145/views"),
            "the lobby's line: free, else what is held"),
    "C13": ("ab", LOBBY, '\tif mode ~= "live" and mode ~= "closed" then\n\t\tline ..= " (TEST: NOTHING IS CHARGED)"',
            '\tif mode == "test" then\n\t\tline ..= " (TEST: NOTHING IS CHARGED)"', A("f0145/views"),
            "in test mode the lobby's line says nothing is charged"),
    "C14": ("ab", LOBBY, 'line = if mode == "closed" then "STORE UNAVAILABLE" else',
            'line = if mode ~= "test" then "STORE UNAVAILABLE" else', A("f0145/views"),
            "the lobby's line: free, else what is held"),
    "C15": ("a", LOBBY, '\t\treturn ""\n\tend\n\treturn ` {Lobby.LIVES_MARK}',
            '\t\treturn ` {Lobby.LIVES_MARK}0`\n\tend\n\treturn ` {Lobby.LIVES_MARK}', A("f0145/lives"),
            "no lives mark for a row without lives"),
    "C16": ("ab", "src/shared/Logic/Hiscores/init.luau", "rank = i,", "rank = 3 - i,", A("f0145/top"), "keep its order"),
    "C17": ("ab", "src/lobby/client/LobbyView.luau", "Lobby.text(drawn, highlight, best, shown)",
            "Lobby.text(drawn, highlight, best, \"all\")", A("d0124/adapters"), "LobbyView adds the best line"),
    # the window's gaps: survive the narrowed specs, caught (if at all) by the spec named
    "W1": ("a", LOBBY, ROW, ROW.replace("{Lobby.livesText(r.lives)}", "{Lobby.livesText(r.lives)} 0"),
           A("f0026/lobby"), "tests/unit/Lobby/boards.spec.luau"),
    "W2": ("a", LOBBY, "return ` {Lobby.LIVES_MARK}{string.format", "return ` {string.format", A("f0145/lives"),
           "none"),
    "W3": ("a", LOBBY, 'else "1 ROBUX A GAME"', 'else "2 ROBUX A GAME"', A("f0145/views"), "none"),
}


def run(spec):
    r = subprocess.run(["lune", "run", "tests/run", "--", spec], cwd=home, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


for spec in (NARROWED, A("d0124/lobby"), A("f0026/lobby"), A("f0145/views")):
    code, out = run(spec)
    print("BASE", spec, "pass" if code == 0 else "FAIL", out.strip().splitlines()[-1])
for mid in (sys.argv[3:] or list(M)):
    bases, rel, old, new, spec, want = M[mid]
    if base not in bases:
        continue
    path = os.path.join(home, rel)
    text = open(path).read()
    assert text.count(old) == 1, (mid, "anchor not found once")
    open(path, "w").write(text.replace(old, new))
    try:
        code, out = run(spec)
        extra = run("tests/unit/Lobby/boards.spec.luau") if mid == "W1" else None
    finally:
        open(path, "w").write(text)
    fails = [l.split(":: ")[-1].strip() for l in out.splitlines() if l.startswith("FAIL") and "::" in l]
    bad = "not an assertion failure" in out or "could not load" in out
    hit = any(want in f for f in fails)
    if mid.startswith("W"):
        verdict = "SURVIVED (gap)" if code == 0 else "killed"
        if extra is not None:
            verdict += f"; unit boards.spec {'kills it' if extra[0] != 0 else 'passes'}"
    else:
        verdict = "ERROR" if bad else ("killed" if code != 0 and hit else ("killed elsewhere" if code != 0 else "SURVIVED"))
    print(mid, verdict, "|", "; ".join(fails))
