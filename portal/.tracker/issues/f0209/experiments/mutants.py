#!/usr/bin/env python3
# f0209 prep's mutation check. Run from the top of the prototype worktree (.worktree/proto2-portal-start-place): c0210's
# own prototype base 4441ae454 (origin/main df6859dbf, R0070's c0194 layer 3c1dee913 merged, f0201's prototype, f0199's
# stand-in, c0194's specs as promoted), then c0210's experiments/prototype.patch, then f0205's and f0208's prototype
# patches without their tracker hunks, then c0210's acceptance specs promoted with lobby-start.spec removed and the AC11
# line dropped from its check.sh (experiments/c0392-standin.patch), then experiments/prototype.patch, with this issue's
# acceptance specs in portal/.tracker/issues/f0209/acceptance/:
#   ./zn run --time 2400 -- python3 -u <this file> [F1 F2 ...]   (no names: every mutant)
# It refuses to run anywhere else, and refuses when a base it was cut from moved (in-flight bases pin their source):
# the five patches and c0210's acceptance folder on origin/main, the base commit, and R0070's c0194 layer. Before any
# mutant it runs this issue's specs and c0210's promoted specs on the unmutated prototype and refuses unless all pass.
# Each mutant replaces texts in files, runs one spec file from portal/, and is "killed" only when the run reports a
# failed case whose message is an assertion ("expected ... got") or a refusal the code raised ("experience.json: ",
# "beta: "), never a load, syntax or require error. Every file is restored after its run.
import hashlib, os, re, subprocess, sys

TOP = os.getcwd()
if not TOP.endswith("/.worktree/proto2-portal-start-place"):
    sys.exit(f"mutants: run from the top of .worktree/proto2-portal-start-place, not {TOP}")

ON_MAIN = {
    "arcade/.tracker/issues/f0201/experiments/prototype.patch": "f99bd914ff800cfc3403ab4000109951694ebebaa2b6d8381d7b8879d6afce7b",
    "portal/.tracker/issues/f0205/experiments/f0199-standin.patch": "feb5ffd388a941f7fe546b66b8922fb16dbe9a3aaef04342b4f566927000a7d6",
    "portal/.tracker/issues/f0205/experiments/prototype.patch": "f6eacbebe360e671ff77379728ab4e6a3449657db5baa006a21ef331bcb1f318",
    "portal/.tracker/issues/f0208/experiments/prototype.patch": "90815701522d457ad49cadaa126a479365f9947dc9014505872f614cf3ab37a2",
    "portal/.tracker/issues/c0210/experiments/prototype.patch": "32d0d930954ad8304a0d4202f5cb8325de8cff535a2c2162425acb7dde3347a3",
}
C0210_SPECS = "6d54e84f09f93d74bd67af0a285d3865c7f3c0904541ef4d45dde5c675f9bd51"
BASE = "4441ae454"
C0194 = ("origin/R0070/1/c0194", "3c1dee913643069edc5b97f10096d8b5fd540bff")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(*args) -> bytes:
    return subprocess.run(["git", *args], capture_output=True, check=True).stdout


def refuse_moved_bases():
    for path, want in ON_MAIN.items():
        got = sha(git("show", f"origin/main:{path}"))
        if got != want:
            sys.exit(f"mutants: {path} on origin/main moved ({got}): recut the base")
    # the same digest as `find acceptance -type f | sort | xargs shasum -a 256 | shasum -a 256` in c0210's folder
    folder = "portal/.tracker/issues/c0210/acceptance"
    names = sorted(git("ls-tree", "--name-only", f"origin/main:{folder}").decode().split())
    lines = "".join(f"{sha(git('show', f'origin/main:{folder}/{n}'))}  acceptance/{n}\n" for n in names)
    got = sha(lines.encode())
    if got != C0210_SPECS:
        sys.exit(f"mutants: c0210's acceptance specs on origin/main moved ({got}): recut the base")
    if subprocess.run(["git", "merge-base", "--is-ancestor", BASE, "HEAD"]).returncode != 0:
        sys.exit(f"mutants: HEAD is not built on {BASE}")
    r = subprocess.run(["git", "rev-parse", C0194[0]], capture_output=True, text=True)
    if r.returncode != 0 or r.stdout.strip() != C0194[1]:
        sys.exit(f"mutants: {C0194[0]} moved or is gone ({r.stdout.strip() or r.stderr.strip()}): recut the base")


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
    (
        "F18",
        [
            (
                SETUP,
                "so every deploy whose event comes after the merge of f0209 publishes the portal there; a run queued or still running at the merge publishes its own older merge (the lobby), and the next deploy corrects it.",
                "so from the merge of f0209 every deploy publishes the portal there.",
            )
        ],
        A + "docs.spec.luau",
    ),
    ("F19", [(RTS, 'for _, attribute in { "PickmanPlaceId", "PortalPlaceId" } do', 'for _, attribute in { "PickmanPlaceId" } do')], A + "runtime.spec.luau"),
    ("F20", [(RTS, 'for _, attribute in { "PickmanPlaceId", "PortalPlaceId" } do', 'for _, attribute in { "PortalPlaceId" } do')], A + "runtime.spec.luau"),
    ("F21", [(RTS, 'type(id) == "number" and id >= 1 and id == math.floor(id)', 'type(id) == "number" and id >= 1')], A + "runtime.spec.luau"),
    ("F22", [(RTS, 'type(id) == "number" and id >= 1 and id == math.floor(id)', 'type(id) == "number"')], A + "runtime.spec.luau"),
    ("F23", [(RTS, 'assert(type(sss:GetAttribute("PaidPlay")) == "string"', "assert(true")], A + "runtime.spec.luau"),
    ("F24", [(RTS, 'assert(game:GetService("Players").CharacterAutoLoads == false', "assert(true")], A + "runtime.spec.luau"),
    ("F25", [(RTS, 'assert(game:GetService("ReplicatedStorage"):FindFirstChild("Arcade")', "assert(true")], A + "runtime.spec.luau"),
    ("F26", [(RTS, 'assert(game:GetService("ServerStorage"):FindFirstChild("Arcade")', "assert(true")], A + "runtime.spec.luau"),
    ("F27", [(RTS, 'sss:FindFirstChild("Lobby") == nil', "true")], A + "runtime.spec.luau"),
    ("F28", [(RTS, 'assert(remotes:FindFirstChild("Snapshot") == nil', "assert(true")], A + "runtime.spec.luau"),
    ("F29", [(RTS, 'assert(server, "ServerScriptService.Server is missing")', "local _ = server")], A + "runtime.spec.luau"),
    ("F30", [(RTS, 'assert(remotes, "ReplicatedStorage.Remotes is missing")', "local _ = remotes")], A + "runtime.spec.luau"),
    ("F31", [(SETUP, " The fix's chore narrows or removes f0209's promoted specs", " The fix's chore narrows what it must")], A + "docs.spec.luau"),
    (
        "F32",
        [(PTEST, " A change that renames a module, a remote or a `Players` property that `tests/runtime/structure.luau` names updates it in the same change.", "")],
        A + "docs.spec.luau",
    ),
    ("F33", [(PTEST, " A script added to or removed from `tests/runtime/` makes z-nile's `c0172/cicd.spec` red under the full gate", " More scripts are welcome")], A + "docs.spec.luau"),
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
base = run([A + f"{s}.spec.luau" for s in SPECS] + sorted("tests/acceptance/c0210/" + n for n in os.listdir("portal/tests/acceptance/c0210") if n.endswith(".spec.luau")))
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
