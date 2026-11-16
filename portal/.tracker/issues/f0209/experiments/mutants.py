#!/usr/bin/env python3
# f0209 prep's mutation check. Run from the top of the prototype worktree (.worktree/proto-portal-start-place: origin/main
# a722ca909 with f0201's, f0199's stand-in, f0205's and f0208's prototype patches, then c0210's prototype.patch and its
# acceptance specs, then experiments/prototype.patch, with c0210's specs promoted and its lobby.spec narrowed as
# experiments/c0392-standin.patch does, and this issue's acceptance specs in portal/.tracker/issues/f0209/acceptance/):
#   ./zn run --time 2400 -- python3 -u <this file> [F1 F2 ...]   (no names: every mutant)
# It refuses to run anywhere else, and refuses when a base it was cut from moved (in-flight bases pin their source):
# the four patches on origin/main and c0210's prototype.patch and acceptance specs in its prep worktree. Before any
# mutant it runs this issue's specs and c0210's promoted specs on the unmutated prototype and refuses unless all pass.
# Each mutant replaces texts in files, runs one spec file from portal/, and is "killed" only when the run reports a
# failed case whose message is an assertion ("expected ... got") or a refusal the code raised ("experience.json: ",
# "beta: ", "is not set", "is missing", "is at the start place"), never a load, syntax or require error. Every file is
# restored after its run.
import glob, hashlib, os, re, subprocess, sys

TOP = os.getcwd()
REPO = os.path.dirname(os.path.dirname(TOP))  # <repo>/.worktree/<name> -> <repo>
if not TOP.endswith("/.worktree/proto-portal-start-place"):
    sys.exit(f"mutants: run from the top of .worktree/proto-portal-start-place, not {TOP}")

ON_MAIN = {
    "arcade/.tracker/issues/f0201/experiments/prototype.patch": "f99bd914ff800cfc3403ab4000109951694ebebaa2b6d8381d7b8879d6afce7b",
    "portal/.tracker/issues/f0205/experiments/f0199-standin.patch": "feb5ffd388a941f7fe546b66b8922fb16dbe9a3aaef04342b4f566927000a7d6",
    "portal/.tracker/issues/f0205/experiments/prototype.patch": "f6eacbebe360e671ff77379728ab4e6a3449657db5baa006a21ef331bcb1f318",
    "portal/.tracker/issues/f0208/experiments/prototype.patch": "90815701522d457ad49cadaa126a479365f9947dc9014505872f614cf3ab37a2",
}
C0210 = os.path.join(REPO, ".worktree/prep-n-place-deploy/portal/.tracker/issues/c0210")
C0210_PATCH = "95cf573c3476914b67048c46fd44e774cf4c1a8e06904654b76c626599a823c9"
C0210_SPECS = "e2cd0c8a863b2c38472f2658b967d12040a56db11f50c84d74233ce6b60f8e9b"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def refuse_moved_bases():
    for path, want in ON_MAIN.items():
        got = sha(subprocess.run(["git", "show", f"origin/main:{path}"], capture_output=True, check=True).stdout)
        if got != want:
            sys.exit(f"mutants: {path} on origin/main moved ({got}): recut the base")
    if not os.path.isdir(C0210):
        sys.exit(f"mutants: c0210's prep is not at {C0210}: read its patch from where it is now and recut")
    got = sha(open(os.path.join(C0210, "experiments/prototype.patch"), "rb").read())
    if got != C0210_PATCH:
        sys.exit(f"mutants: c0210's prototype.patch moved ({got}): recut the base")
    # the same digest as `find acceptance -type f | sort | xargs shasum -a 256 | shasum -a 256` in c0210's folder
    lines = ""
    for f in sorted(glob.glob(os.path.join(C0210, "acceptance", "*"))):
        lines += f"{sha(open(f, 'rb').read())}  acceptance/{os.path.basename(f)}\n"
    got = sha(lines.encode())
    if got != C0210_SPECS:
        sys.exit(f"mutants: c0210's acceptance specs moved ({got}): recut the base")


A = ".tracker/issues/f0209/acceptance/"  # relative to portal/, where these specs run
MAN = "portal/experience.json"
RTS = "portal/tests/runtime/structure.luau"
SETUP = "SETUP.md"
PTEST = "portal/skills/portal-test/SKILL.md"
KTEST = "pickman/skills/pickman-test/SKILL.md"
LOBBY_BUILD = (
    '    "lobby": {\n'
    '      "project": "../pickman/lobby.project.json",\n'
    '      "runtime": "../pickman/tests/runtime/lobby",\n'
    '      "attributes": { "GamePlaceId": "Pickman" }\n'
    "    },\n"
)

# name, [(file, old, new)], spec (from portal/)
MUTANTS = [
    ("F1", [(MAN, '"build": "portal"', '"build": "lobby"')], A + "start.spec.luau"),
    ("F2", [(MAN, ', "runtime": "tests/runtime" }', " }")], A + "runtime.spec.luau"),
    ("F3", [(MAN, '"runtime": "tests/runtime" }', '"runtime": "tests/runtime", "attributes": { "GamePlaceId": "Pickman" } }')], A + "start.spec.luau"),
    (
        "F4",
        [
            (MAN, '"build": "portal"', '"build": "lobby"'),
            (MAN, '"project": "../pickman/lobby.project.json"', '"project": "default.project.json"'),
        ],
        A + "start.spec.luau",
    ),
    ("F5", [(MAN, '"output": "lobby_version"', '"output": "portal_version"')], A + "deploy.spec.luau"),
    (
        "F6",
        [
            (RTS, 'for _, name in { "Main", "Cards", "Plays" } do', 'for _, name in { "Main" } do'),
            (RTS, 'for _, name in { "Cards", "Play" } do', "for _, name in {} do"),
            (RTS, 'assert(remotes:FindFirstChild("Snapshot") == nil', "assert(true"),
        ],
        A + "runtime.spec.luau",
    ),
    ("F7", [(RTS, 'for _, attribute in { "PickmanPlaceId", "PortalPlaceId" } do', "for _, attribute in {} do")], A + "runtime.spec.luau"),
    ("F8", [(MAN, '"runtime": "tests/runtime" }', '"runtime": "../pickman/tests/runtime/lobby" }')], A + "runtime.spec.luau"),
    ("F9", [(MAN, '"attributes": { "LobbyPlaceId": "Portal" }', '"attributes": { "LobbyPlaceId": "Pickman" }')], A + "deploy.spec.luau"),
    ("F10", [(MAN, LOBBY_BUILD, "")], A + "rollback.spec.luau"),
    ("F11", [(MAN, '"build": "pickman"', '"build": "lobby"')], A + "start.spec.luau"),
    (
        "F12",
        [
            (
                SETUP,
                "(the portal, `portal/default.project.json`, since f0209; before it pickman's lobby, `pickman/lobby.project.json`)",
                "(pickman's lobby, `pickman/lobby.project.json`, until the portal replaces it)",
            )
        ],
        A + "docs.spec.luau",
    ),
    ("F13", [(SETUP, "- **Rolling the start place back**", "- **Rolling back**")], A + "docs.spec.luau"),
    ("F14", [(PTEST, "- `tests/runtime/` holds the start place's runtime scripts (f0209)", "- `tests/runtime/` holds runtime scripts")], A + "docs.spec.luau"),
    ("F15", [(KTEST, " before f0209, or after a rollback of it; the portal's own are `portal/tests/runtime/`", "")], A + "docs.spec.luau"),
    ("F16", [("pickman/.tracker/game-design.md", " Since f0209 the experience's start place is the portal", " The lobby stays")], A + "docs.spec.luau"),
    ("F17", [("portal/" + A + "deploy.spec.luau", '\t\te[var] = ""\n', "\t\tlocal _ = var\n")], A + "deploy.spec.luau"),
]

SPECS = ["start", "deploy", "runtime", "rollback", "docs"]


def run(spec_args):
    r = subprocess.run(
        ["lune", "run", "tests/run", "--"] + spec_args, cwd=os.path.join(TOP, "portal"), capture_output=True, text=True, timeout=900
    )
    return r.stdout + r.stderr


def counts(out):
    m = re.search(r"(\d+) passed, (\d+) failed, \d+ spec files", out)
    return (int(m.group(1)), int(m.group(2))) if m else (-1, -1)


refuse_moved_bases()
base = run([A + f"{s}.spec.luau" for s in SPECS] + [p[len("portal/") :] for p in sorted(glob.glob("portal/tests/acceptance/c0210/*.spec.luau"))])
passed, failed = counts(base)
print(f"base: {passed} passed, {failed} failed")
if failed != 0 or passed <= 0:
    print(base)
    sys.exit("mutants: the unmutated prototype is not green; nothing was mutated")

only = set(sys.argv[1:])
for name, edits, spec in MUTANTS:
    if only and name not in only:
        continue
    saved = {}
    ok = True
    for path, old, new in edits:
        text = saved.get(path) or open(path).read()
        saved.setdefault(path, text)
        current = open(path).read()
        if current.count(old) != 1:
            print(f"{name}: NOT APPLIED ({current.count(old)} matches of an edit in {path})")
            ok = False
            break
        open(path, "w").write(current.replace(old, new))
    try:
        out = run([spec]) if ok else ""
    finally:
        for path, text in saved.items():
            open(path, "w").write(text)
    if not ok:
        continue
    _, failed = counts(out)
    assertion = re.search(r"expected .*?got|beta: |experience\.json: ", out, re.S) is not None
    broken = re.search(r"could not load spec|Unable to require|Syntax|syntax error", out) is not None
    verdict = "killed" if failed > 0 and assertion and not broken else ("SURVIVED" if failed == 0 else "ERROR (not an assertion)")
    cases = [l.strip() for l in out.splitlines() if l.strip().startswith("FAIL ") and "::" in l]
    print(f"{name}: {verdict} ({failed} failed) {spec}")
    for c in cases[:4]:
        print(f"    {c}")
