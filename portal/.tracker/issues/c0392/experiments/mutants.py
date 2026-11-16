#!/usr/bin/env python3
# c0392 prep's window check: which deploy mutants that c0210's lobby-start.spec kills does a remaining c0210 spec still
# kill? Run from the top of the prototype checkout at its "c0210 done" commit (c0210's acceptance promoted into
# portal/tests/acceptance/c0210/, lobby-start.spec still there), with nothing uncommitted:
#   ./zn run --time 1800 -- python3 -I -u <this file> [L1 L2 ...]   (no names: every mutant)
# Each mutant replaces one text in one file (refused unless it occurs exactly once), runs lobby-start.spec, then the
# other c0210 specs in one run, from portal/, and restores the file. A run kills only when it reports a failed case
# with an assertion ("expected ... got") or a refusal of the code under test ("beta: ", "experience.json: ") and no
# load error. Every file is restored after its run, and the tree must be clean before and after.
import glob, re, subprocess, sys

MAN = "portal/experience.json"
DEPLOY = "portal/scripts/deploy-beta.luau"
C = "tests/acceptance/c0210/"  # from portal/
LOBBY_RUNTIME = '      "runtime": "../pickman/tests/runtime/lobby",\n'
LOBBY_ATTRS = '      "attributes": { "GamePlaceId": "Pickman" }\n'

MUTANTS = [
    ("L1", MAN, '"build": "lobby"', '"build": "portal"', "the start place publishes the portal (f0209's switch, early)"),
    ("L2", MAN, LOBBY_RUNTIME + LOBBY_ATTRS, '      "runtime": "../pickman/tests/runtime/lobby"\n', "the lobby is not told GamePlaceId"),
    ("L3", MAN, '"GamePlaceId": "Pickman"', '"GamePlaceId": "Snake"', "the lobby's GamePlaceId is Snake's id"),
    ("L4", MAN, LOBBY_RUNTIME, "", "the lobby build has no runtime folder (--place Portal skips)"),
    ("L5", MAN, '{ "GamePlaceId": "Pickman" }', '{ "GamePlaceId": "Pickman", "LobbyPlaceId": "Portal" }', "the lobby is told LobbyPlaceId too"),
    ("L6", MAN, '"output": "lobby_version"', '"output": "start_version"', "the start place's output renamed"),
    ("L7", DEPLOY, "\ttable.insert(lines, `{target.output}={result}`)", "\ttable.insert(lines, 1, `{target.output}={result}`)", "the outputs written last place first"),
    ("L8", DEPLOY, "for i, target in plan.targets do\n\tlocal placeCfg", "for i = #plan.targets, 1, -1 do\n\tlocal target = plan.targets[i]\n\tlocal placeCfg", "the start place published first"),
]


def run(specs):
    r = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd="portal", capture_output=True, text=True, timeout=900)
    out = r.stdout + r.stderr
    m = re.search(r"(\d+) passed, (\d+) failed, (\d+) spec files?", out)
    failed = int(m.group(2)) if m else -1
    assertion = re.search(r"expected .*?got|beta: |experience\.json: ", out, re.S) is not None
    broken = re.search(r"could not load spec|attempt to |Unable to require|Syntax|syntax error", out) is not None
    if failed > 0 and assertion and not broken:
        verdict = "killed"
    elif failed == 0 and m:
        verdict = "survived"
    else:
        verdict = "ERROR"
    cases = [l.split(" :: ", 1)[0].split()[-1] + " :: " + l.split(" :: ", 1)[1] for l in out.splitlines() if l.startswith("FAIL ") and " :: " in l]
    return verdict, (m.group(0) if m else "no result line"), cases


def clean():
    return subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], capture_output=True, text=True).stdout == ""


if not clean():
    sys.exit("the tree has uncommitted changes: commit or stash first")
others = sorted(p[len("portal/"):] for p in glob.glob("portal/" + C + "*.spec.luau") if not p.endswith("/lobby-start.spec.luau"))
if len(others) != 10 or not glob.glob("portal/" + C + "lobby-start.spec.luau"):
    sys.exit(f"expected lobby-start.spec and 10 other c0210 specs in portal/{C}, found {len(others)}")
print("unmutated:", "lobby-start", run([C + "lobby-start.spec.luau"])[:2], "others", run(others)[:2])
only = set(sys.argv[1:])
for name, path, old, new, what in MUTANTS:
    if only and name not in only:
        continue
    text = open(path).read()
    if text.count(old) != 1:
        print(f"{name}: NOT APPLIED ({text.count(old)} matches in {path})")
        continue
    open(path, "w").write(text.replace(old, new))
    try:
        ls = run([C + "lobby-start.spec.luau"])
        ot = run(others)
    finally:
        open(path, "w").write(text)
    print(f"{name} ({what}): lobby-start {ls[0]} ({ls[1]}); others {ot[0]} ({ot[1]})")
    for c in ot[2][:4]:
        print(f"    FAIL {c}")
if not clean():
    sys.exit("the tree was left changed")
