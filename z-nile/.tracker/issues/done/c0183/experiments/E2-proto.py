# c0183 E2 prototype: applies the intended implementation (Design items 1 to 7 and the overrides) to the checkout
# given as argv[1]. argv[2] names a mutant (Rules and mutants) or is absent for the correct implementation.
# Afterwards: stylua over the changed .luau files, then E2-rehash.py (c0172's digests).
import pathlib, re, sys

R = pathlib.Path(sys.argv[1])
mutant = sys.argv[2] if len(sys.argv) > 2 else ""
NEW = ["arcade", "portal", "snake", "invaders", "asteroids"]


def sub(path, old, new):
    p = R / path
    t = p.read_text()
    assert old in t, (path, old[:70])
    p.write_text(t.replace(old, new, 1))


# 1. the registry
order = NEW if mutant != "order" else ["portal", "arcade", "snake", "invaders", "asteroids"]
reg = R / "z-nile/projects.toml"
reg.write_text(reg.read_text().rstrip("\n") + "\n"
               + "".join(f'\n[[project]]\nname = "{n}"\nroot = "{n}/.tracker"\n' for n in order))
ROOTS = ["pickman/.tracker", "z-nile/.tracker"] + [f"{n}/.tracker" for n in NEW]

# 2. the roots
for n in NEW:
    for k in ["issues/active/.gitkeep", "rafts/active/.gitkeep"]:
        if mutant == "nokeep" and n == "asteroids" and k.startswith("rafts"):
            continue
        p = R / n / ".tracker" / k
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("")

# 3. the moved designs (the same transform as E4-digests.py)
doc = next((R / "z-nile/.tracker/issues").glob("**/c0183/c0183.md")).read_text().split("\n")
G = ("The source of truth for this project's product decisions, from the user's request of 2026-10-31 "
     "(captured in c0183). Every design in this project must agree with it. Changes happen through the user, never "
     "during execution.")
A = ("The shared library's design, from the plan the user approved on 2026-10-31 (captured in c0183). "
     "Every design that uses the library must agree with it; changing it is a design decision, made in z-design.")
for f, title, note, frm, to in [
        ("snake/.tracker/game-design.md", "Snake game design", G, None, None),
        ("invaders/.tracker/game-design.md", "Invaders game design", G, None, None),
        ("asteroids/.tracker/game-design.md", "Asteroids game design", G, None, None),
        ("portal/.tracker/game-design.md", "Portal game design", G, None, None),
        ("arcade/.tracker/architecture.md", "Arcade architecture", A, "##### Context", "##### Tracker work")]:
    s = next(i for i, l in enumerate(doc) if l.startswith("#### `" + f + "`"))
    block = []
    for l in doc[s + 1:]:
        if re.match(r"^#### `", l) or re.match(r"^##? ", l) or re.match(r"^### ", l):
            break
        block.append(l)
    i = 0
    while block[i] == "":
        i += 1
    while i < len(block) and block[i] != "":
        i += 1
    body, keep = [], frm is None
    for l in block[i:]:
        if frm and l.startswith(frm):
            keep = True
        elif to and l.startswith(to) and mutant != "keeplist":
            keep = False
        if keep:
            body.append(re.sub(r"^##### ", "## ", l))
    while body and body[0] == "":
        body.pop(0)
    while body and body[-1] == "":
        body.pop()
    if mutant == "verbatim-heading":
        body = [re.sub(r"^## ", "##### ", l) for l in body]
    (R / f).write_text(f"# {title}\n\n{note}\n\n" + "\n".join(body) + "\n")

# 4. the stub maps
for n, t in [("portal", "Portal"), ("snake", "Snake"), ("invaders", "Invaders"), ("asteroids", "Asteroids")]:
    (R / n / ".tracker/architecture.md").write_text(
        f"# {t} architecture\n\nNo code yet: c0184 scaffolds this home and c0185 gates code shared across "
        "homes. Shared code comes from the `arcade` library (`arcade/.tracker/architecture.md`). This file grows "
        "with the project's first design.\n")

# 5. deploy.yml: every root, in registry order, then the counter
sub(".github/workflows/deploy.yml", "paths-ignore: ['pickman/.tracker/**', 'z-nile/.tracker/**', 'z-nile/next']",
    "paths-ignore: [" + ", ".join(f"'{r}/**'" for r in ROOTS) + ", 'z-nile/next']")

# 6. docs
PIN = ("The game is the `pickman` project, in `pickman/` (its `src/`, specs, Rojo projects and issues, "
       "`pickman/.tracker/`); the tooling that tracks and gates it is `z-nile/` (zz-rules skill, Projects).")
if mutant != "nodocs":
    sub("AGENTS.md", PIN, PIN + " The arcade's projects are registered too (c0183): `arcade/` (the library every place "
        "shares), `portal/` (the experience's start place) and the games `snake/`, `invaders/` and `asteroids/`; each "
        "keeps its product decisions in `<name>/.tracker/game-design.md`, and the library its design in "
        "`arcade/.tracker/architecture.md`.")
P2 = "A game is a project: pickman is one, in `pickman/`."
sub("z-nile/README.md", P2, P2 + " The arcade adds five more (c0183): the shared library `arcade`, the start place "
    "`portal`, and the games `snake`, `invaders` and `asteroids`, each in its own folder.")
sub("z-nile/skills/zz-rules/SKILL.md",
    "`deploy.yml` ignores `pickman/.tracker/**`, `z-nile/.tracker/**` and `z-nile/next` on `push`. Adding a project "
    "needs a registry entry only.",
    "`deploy.yml` ignores every project root (`<root>/**`: `pickman/.tracker/**`, `z-nile/.tracker/**` and the rest, "
    "in registry order) and `z-nile/next` on `push`. Adding a project needs its registry entry and its root in that "
    "`deploy.yml` list.")

# overrides: c0120 docs (the zz-rules sentences)
sub("z-nile/tests/acceptance/c0120/docs.spec.luau",
    '\t\tat(s, "Adding a project needs a registry entry only.", w)',
    "\t\t-- c0183 override: a new root also joins deploy.yml's ignore list (c0114's gate-cover spec requires it)\n"
    '\t\tat(s, "Adding a project needs its registry entry and its root in that `deploy.yml` list.", w)')
sub("z-nile/tests/acceptance/c0120/docs.spec.luau",
    '\t\t\t"`deploy.yml` ignores `pickman/.tracker/**`, `z-nile/.tracker/**` and `z-nile/next` on `push`.",',
    "\t\t\t-- c0183 override: every root, in registry order\n"
    '\t\t\t"`deploy.yml` ignores every project root (`<root>/**`: `pickman/.tracker/**`, `z-nile/.tracker/**` and the '
    'rest, in registry order) and `z-nile/next` on `push`.",')

# overrides: the three pins of the ignore list, derived from the registry
LIST_OLD = '.toEqual({ "pickman/.tracker/**", "z-nile/.tracker/**", "z-nile/next" })'


# the shared helper: deploy.yml's ignore list as the registry implies it (one copy, for gate-cover and ci)
(R / "z-nile/tests/lib/deploylist.luau").write_text(
    "--!strict\n"
    "-- c0183: deploy.yml's push paths-ignore as the registry implies it: every project root `<root>/**`, in registry\n"
    "-- order, then the counter `z-nile/next`. The one copy of that list for the specs that pin it (c0114's gate-cover,\n"
    "-- c0120's ci), so a new project needs its deploy.yml entry and no spec edit.\n"
    'local projects = require("@znile/engine/projects")\n\n'
    "local deploylist = {}\n\n"
    "-- the list for the checkout whose top is `top`\n"
    "function deploylist.ignored(top: string): { string }\n"
    "\tlocal out: { string } = {}\n"
    "\tfor _, r in projects.roots(projects.load(top)) do\n"
    "\t\ttable.insert(out, `{r}/**`)\n"
    "\tend\n"
    '\ttable.insert(out, "z-nile/next")\n'
    "\treturn out\n"
    "end\n\n"
    "return deploylist\n")
for f, top in [("z-nile/tests/acceptance/c0120/ci.spec.luau", "TOP"),
               ("z-nile/tests/acceptance/c0114/gate-cover.spec.luau", "root")]:
    q = R / f
    s = q.read_text()
    assert LIST_OLD in s, f
    s = s.replace('local t = require("@tests/lib/t")',
                  'local deploylist = require("@tests/lib/deploylist")\nlocal t = require("@tests/lib/t")', 1)
    s = s.replace(LIST_OLD, f".toEqual(deploylist.ignored({top})) -- c0183 override: every registered root, then the counter")
    q.write_text(s)
# pickman's c0015: its own concern only, the list's shape (no registry read; c0120's graph-homes keeps the homes apart)
sub("pickman/tests/acceptance/c0015/workflow.spec.luau",
    '\t\t\tt.expect(on.push["paths-ignore"])\n\t\t\t\t.toEqual({ "pickman/.tracker/**", "z-nile/.tracker/**", "z-nile/next" })',
    "\t\t\t-- c0183 override: pickman's own concern, the shape of the list: its root and the counter are ignored, and every\n"
    "\t\t\t-- other entry is a project root `<name>/.tracker/**` (the exact list, against the registry, is gate-cover's and ci's)\n"
    '\t\t\tlocal ignored: { string } = on.push["paths-ignore"]\n'
    '\t\t\tt.expect(table.find(ignored, "pickman/.tracker/**") ~= nil).toBe(true)\n'
    '\t\t\tt.expect(table.find(ignored, "z-nile/next") ~= nil).toBe(true)\n'
    "\t\t\tfor _, e in ignored do\n"
    '\t\t\t\tt.expect(e == "z-nile/next" or string.match(e, "^[a-z][a-z0-9%-]*/%.tracker/%*%*$") ~= nil).toBe(true)\n'
    "\t\t\tend")
sub("z-nile/tests/acceptance/c0114/gate-cover.spec.luau",
    '"every root of the registry reaches every gate site, so a new root needs only its registry entry",',
    "-- c0183 override: the case also needs each root in deploy.yml (below), so the name says so\n"
    '\t\t"every root of the registry reaches every gate site, so a new root needs its registry entry and its '
    'deploy.yml entry",')

# overrides: c0114 registry and c0120 registry-home, the rule (pickman, then z-nile, first; every entry at
# <name>/.tracker with home <name>) instead of today's list
TWO = ('\t\t\tt.expect(r.projects).toEqual({\n'
       '\t\t\t\t{ name = "pickman", root = "pickman/.tracker", home = "pickman" },\n'
       '\t\t\t\t{ name = "z-nile", root = "z-nile/.tracker", home = "z-nile" },\n'
       '\t\t\t})')
RULE = ('\t\t\t-- c0183 override: the rule, not today\'s list (more projects follow the first two)\n'
        '\t\t\tt.expect(r.projects[1]).toEqual({ name = "pickman", root = "pickman/.tracker", home = "pickman" })\n'
        '\t\t\tt.expect(r.projects[2]).toEqual({ name = "z-nile", root = "z-nile/.tracker", home = "z-nile" })\n'
        '\t\t\tlocal rootsInOrder: { string } = {}\n'
        '\t\t\tfor _, p in r.projects do\n'
        '\t\t\t\tt.expect(p).toEqual({ name = p.name, root = `{p.name}/.tracker`, home = p.name })\n'
        '\t\t\t\ttable.insert(rootsInOrder, p.root)\n'
        '\t\t\tend')
sub("z-nile/tests/acceptance/c0114/registry.spec.luau", TWO, RULE)
sub("z-nile/tests/acceptance/c0114/registry.spec.luau",
    't.expect(projects.roots(r)).toEqual({ "pickman/.tracker", "z-nile/.tracker" })',
    't.expect(projects.roots(r)).toEqual(rootsInOrder)')
sub("z-nile/tests/acceptance/c0120/registry-home.spec.luau", TWO, RULE)
sub("z-nile/tests/acceptance/c0120/registry-home.spec.luau",
    't.expect(projects.allRoots(r)).toEqual({ "pickman/.tracker", "z-nile/.tracker", "tracker" })',
    'table.insert(rootsInOrder, "tracker")\n\t\t\tt.expect(projects.allRoots(r)).toEqual(rootsInOrder)')
sub("z-nile/tests/acceptance/c0120/registry-home.spec.luau",
    't.expect(r.stdout).toBe("pickman\\tpickman\\tpickman/.tracker\\nz-nile\\tz-nile\\tz-nile/.tracker\\n")',
    '-- c0183 override: one line per registered project, in registry order, derived from the registry\n'
    '\t\t\tlocal reg = projects.parse(fs.readFile(`{TOP}/z-nile/projects.toml`)) :: projects.Registry\n'
    '\t\t\tlocal want = ""\n'
    '\t\t\tfor _, p in reg.projects do\n'
    '\t\t\t\twant ..= `{p.name}\\t{p.home}\\t{p.root}\\n`\n'
    '\t\t\tend\n'
    '\t\t\tt.expect(r.stdout).toBe(want)')

# overrides: c0114 classified, the copy holds every registered root, so the fence finds every home
if mutant != "copy-pickman-only":
    sub("z-nile/tests/acceptance/c0114/classified.spec.luau",
        '\tlocal listed = process.exec(\n'
        '\t\t"git",\n'
        '\t\t{ "ls-files", "-co", "--exclude-standard", "zn", "scripts", "z-nile", "pickman/.tracker" },\n'
        '\t\t{ cwd = TOP }\n'
        '\t)',
        "\t-- c0183 override: every registered root, so the fence (which refuses a home missing from the tree) finds each\n"
        "\t-- home\n"
        '\tlocal args = { "ls-files", "-co", "--exclude-standard", "zn", "scripts", "z-nile" }\n'
        "\tfor _, root in projects.roots(projects.load(TOP)) do\n"
        '\t\tif root ~= "z-nile/.tracker" then\n'
        "\t\t\ttable.insert(args, root)\n"
        "\t\tend\n"
        "\tend\n"
        '\tlocal listed = process.exec("git", args, { cwd = TOP })')
# the skills' restated project rules (design review 002 F1)
sub("z-nile/skills/zz-rules/SKILL.md",
    "pickman's is `pickman/.tracker/` and z-nile's, the tooling's, is `z-nile/.tracker/`.",
    "pickman's is `pickman/.tracker/` and z-nile's, the tooling's, is `z-nile/.tracker/`. " + "The arcade's projects keep theirs the same way, `<name>/.tracker/` with the home `<name>/` (c0183: `arcade`, `portal`, `snake`, `invaders`, `asteroids`).")
sub("z-nile/skills/z-ticket/SKILL.md",
    "game work is `--project pickman`, or a capture run in `pickman/` (zz-rules skill, Projects)",
    "the work of a game, the portal or the arcade library is its project's (`--project pickman`, `--project snake`, "
    "`--project portal`, `--project arcade`, …: a name in `z-nile/projects.toml`), or a capture run in that project's folder "
    "(`pickman/`, `snake/`, …) (zz-rules skill, Projects)")
sub("z-nile/skills/zz-rules/SKILL.md",
    "There, game work passes `--project pickman` and tooling (the tracker, the gate, the guards, the skills) `--project z-nile`.",
    "There, the work of a game, the portal or the arcade library passes its project (`--project pickman`, "
    "`--project snake`, `--project portal`, `--project arcade`, …: a name in `z-nile/projects.toml`) and tooling (the "
    "tracker, the gate, the guards, the skills) `--project z-nile`.")
sub("z-nile/skills/zz-rules/SKILL.md",
    "(`<root>` is the item's project root, `pickman/.tracker` or `z-nile/.tracker`)",
    "(`<root>` is the item's project root, `<name>/.tracker` for a project of `z-nile/projects.toml`, such as "
    "`pickman/.tracker` or `z-nile/.tracker`)")
sub("z-nile/tests/acceptance/c0114/docs.spec.luau",
    '\t\tat(make, "game work is `--project pickman`, or a capture run in `pickman/`")',
    "\t\t-- c0183 override: a game's, the portal's or the library's work is its own project's, pickman one of them\n"
    '\t\tat(make, "the work of a game, the portal or the arcade library is its project\'s (`--project pickman`")')
if mutant == "stale-skills":
    sub("z-nile/skills/zz-rules/SKILL.md", "`<name>/.tracker` for a project of `z-nile/projects.toml`, such as ", "")
print("applied", mutant or "correct")
