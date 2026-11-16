#!/usr/bin/env python3
# c0210 prep's mutation check. Run from the prototype's checkout top (a scratch worktree with experiments/prototype.patch
# applied and this issue's acceptance specs in portal/.tracker/issues/c0210/acceptance/):
#   ./zn run --time 2400 -- python3 -u <this file> [M1 P2 ...]   (no names: every mutant)
# Each mutant replaces one text in one file, runs the named spec file from its home, and passes ("killed") only when
# the run reports a failed case whose message is an assertion ("expected ... got") or a refusal the code under test
# raised itself ("beta: ...", "experience.json: ..."), never a load, syntax or require error ("could not load spec",
# "attempt to", "Unable to require", "Syntax"). Every file is restored after its run.
import re, subprocess, sys

A = ".tracker/issues/c0210/acceptance/"  # relative to portal/, where these specs run
EXP = "portal/scripts/lib/experience.luau"
BETA = "portal/scripts/lib/beta.luau"
DEPLOY = "portal/scripts/deploy-beta.luau"
RT = "portal/scripts/runtime-test.luau"
MAN = "portal/experience.json"
WF = ".github/workflows/deploy.yml"

MUTANTS = [
    ("M1", EXP, 'return fail(`place {name} is missing: every place of Places.NAMES is listed`)', 'continue', "portal", A + "manifest.spec.luau"),
    ("M2", EXP, '"^ROBLOX_BETA_[A-Z0-9_]*PLACE_ID$"', '"^[A-Za-z_]+$"', "portal", A + "manifest.spec.luau"),
    ("M3", EXP, "if vars[var] then", "if false then", "portal", A + "manifest.spec.luau"),
    ("M4", EXP, "if #env ~= 1 then", "if false then", "portal", A + "manifest.spec.luau"),
    ("M5", EXP, "if used[build] then", "if false then", "portal", A + "manifest.spec.luau"),
    ("M6", EXP, "if table.find(reserved, attribute) then", "if false then", "portal", A + "manifest.spec.luau"),
    ("M7", EXP, "if occurrences(text, key) ~= counted[key] then", "if false then", "portal", A + "manifest.spec.luau"),
    ("M8", MAN, '"env": ["ROBLOX_BETA_PICKMAN_PLACE_ID", "ROBLOX_BETA_GAME_PLACE_ID"]', '"env": ["ROBLOX_BETA_GAME_PLACE_ID", "ROBLOX_BETA_PICKMAN_PLACE_ID"]', "portal", A + "manifest.spec.luau"),
    ("M9", MAN, '"output": "lobby_version"', '"output": "start_version"', "portal", A + "lobby-start.spec.luau"),
    ("P1", BETA, 'if value ~= nil and value ~= "" then', "if value ~= nil then", "portal", A + "plan.spec.luau"),
    ("P2", BETA, "table.insert(games, start)", "table.insert(games, 1, start)", "portal", A + "plan.spec.luau"),
    ("P3", BETA, "out[Places.attribute(name :: Places.Name)] = ids[name] or 0", "out[Places.attribute(name :: Places.Name)] = ids[name]", "portal", A + "plan.spec.luau"),
    ("P4", BETA, "for _, var in place.env do", "for _, var in { place.env[1] } do", "portal", A + "plan.spec.luau"),
    ("P5", BETA, "elseif found ~= value then", "elseif false then", "portal", A + "plan.spec.luau"),
    ("P6", BETA, 'if not string.match(value, "^[1-9]%d*$") or n == nil or n > Beta.MAX_PLACE_ID then', 'if not string.match(value, "^%d+$") then', "portal", A + "plan.spec.luau"),
    ("P7", BETA, "if owner[id] then", "if false then", "portal", A + "plan.spec.luau"),
    ("P8", BETA, "out[Experience.PAID_PLAY] = Beta.PAID_PLAY_MODE", "", "portal", A + "plan.spec.luau"),
    ("P9", BETA, "attributes[attribute] = ids[name] or 0", "", "portal", A + "way-back.spec.luau"),
    ("D1", DEPLOY, "\ttable.insert(files, out)\nend\n", "\ttable.insert(files, out)\n\tlocal pc = table.clone(cfg)\n\tpc.placeId = target.placeId\n\tpcall(OpenCloud.publish, pc, fs.readFile(out))\nend\n", "portal", A + "deploy.spec.luau"),
    ("D2", BETA, "\t\tif id then\n\t\t\tlocal build", "\t\tif true then\n\t\t\tid = id or \"999\"\n\t\t\tlocal build", "portal", A + "deploy.spec.luau"),
    ("D3", DEPLOY, '\tprint(`published the {target.name} place ({target.placeId}): version {result}`)\n\ttable.insert(lines, `{target.output}={result}`)', '\tprint(`published the {target.name} place ({target.placeId}): version {result}`)\n\ttable.insert(lines, `{target.output}={result}`)\n\tlocal gh = process.env.GITHUB_OUTPUT\n\tif gh and gh ~= "" then\n\t\tfs.writeFile(gh, (if fs.isFile(gh) then fs.readFile(gh) else "") .. `{target.output}={result}\\n`)\n\tend', "portal", A + "deploy.spec.luau"),
    ("D4", DEPLOY, "local manifestPath = `{root}/{Experience.FILE}`", "local manifestPath = `{(string.match(debug.info(1, \"s\"), \"^(.*)/scripts/\") or root)}/{Experience.FILE}`", "portal", A + "deploy.spec.luau"),
    ("R1", RT, 'local place = "Pickman"', 'local place = "Portal"', "portal", A + "runtime.spec.luau"),
    ("R2", RT, "if target == nil then\n\tprint(`::warning::runtime tests of the", "if false then\n\tprint(`::warning::runtime tests of the", "portal", A + "runtime.spec.luau"),
    ("R3", RT, "if not known then", "if false then", "portal", A + "runtime.spec.luau"),
    ("R4", RT, "\ttable.sort(files)\n", "\ttable.sort(files, function(a, b) return a > b end)\n", "portal", A + "runtime.spec.luau"),
    ("W1", WF, "          ROBLOX_BETA_SNAKE_PLACE_ID: ${{ vars.ROBLOX_BETA_SNAKE_PLACE_ID }}\n", "", "portal", A + "workflow.spec.luau"),
    ("W2", WF, "        working-directory: portal\n", "        working-directory: pickman\n", "portal", A + "workflow.spec.luau"),
    ("B1", BETA, "out[Experience.PAID_PLAY] = Beta.PAID_PLAY_MODE", "out[Experience.PAID_PLAY] = 0", "portal", A + "build.spec.luau"),
    ("L1", MAN, '"build": "lobby"', '"build": "portal"', "portal", A + "lobby-start.spec.luau"),
    ("X1", "SETUP.md", "`lune run scripts/runtime-test -- --place Portal <lobby version>`", "`lune run scripts/runtime-test -- --lobby <lobby version>`", "portal", A + "layout.spec.luau"),
    ("C1", "portal/scripts/cicd.luau", '{ "--place", "Portal", lobbyVersion :: string }', '{ "--lobby", lobbyVersion :: string }', "z-nile", "tests/acceptance/c0172/cicd.spec.luau"),
    # design review 001: F1 (the overrides' goldens and digests), F2 (the child's blanks), F3 (the reader), F7
    ("O1", "pickman/tests/acceptance/c0064/plan.spec.luau", '\t\t\tt.expect(type(lobby.attributes.GamePlaceId)).toBe("number")\n', "", "portal", A + "overrides.spec.luau"),
    ("O2", "pickman/tests/acceptance/c0015/deploy-e2e.spec.luau", '\n\t\tt.expect(seen[1].contentType).toBe("application/octet-stream")', ' -- t.expect(seen[1].contentType).toBe("application/octet-stream")', "portal", A + "overrides.spec.luau"),
    ("O3", "pickman/tests/acceptance/c0003/runner-e2e.spec.luau", '\tit("all scripts passing: exit 0 and a report", function()\n', '\tit("all scripts passing: exit 0 and a report", function()\n\t\tdo return end\n', "portal", A + "overrides.spec.luau"),
    ("O4", "pickman/tests/acceptance/c0051/retry.spec.luau", "--!strict\n", "--!strict\n-- an edit\n", "portal", A + "overrides.spec.luau"),
    ("E1", "portal/" + A + "deploy.spec.luau", '\t\t\tout[var] = ""\n', "", "portal", A + "deploy.spec.luau"),
    ("E2", "portal/" + A + "runtime.spec.luau", '\t\t\tout[var] = ""\n', "", "portal", A + "runtime.spec.luau"),
    ("M10", EXP, 'if string.find(text, "\\\\", 1, true) then', "if false then", "portal", A + "manifest.spec.luau"),
    ("M11", EXP, "\t\tinto[k] = (into[k] or 0) + 1\n", "\t\tif table.find(FIELDS, k) then\n\t\t\tinto[k] = (into[k] or 0) + 1\n\t\tend\n", "portal", A + "manifest.spec.luau"),
    ("M12", EXP, "\t\tif same then\n", "\t\tif false and same then\n", "portal", A + "manifest.spec.luau"),
    ("R5", RT, 'if args[1] == "--place" then', 'if args[1] == "--place" and tonumber(args[2]) ~= nil then\n\ttable.remove(args, 1)\nelseif args[1] == "--place" then', "portal", A + "runtime.spec.luau"),
    ("P10", BETA, "\t\tout[entry.revive] = 0\n", "", "portal", A + "plan.spec.luau"),
]


def run(home, spec):
    r = subprocess.run(["lune", "run", "tests/run", "--", spec], cwd=home, capture_output=True, text=True, timeout=900)
    return r.stdout + r.stderr


only = set(sys.argv[1:])
for name, path, old, new, home, spec in MUTANTS:
    if only and name not in only:
        continue
    text = open(path).read()
    if text.count(old) != 1:
        print(f"{name}: NOT APPLIED ({text.count(old)} matches in {path})")
        continue
    open(path, "w").write(text.replace(old, new))
    try:
        out = run(home, spec)
    finally:
        open(path, "w").write(text)
    m = re.search(r"(\d+) passed, (\d+) failed, \d+ spec files", out)
    failed = int(m.group(2)) if m else -1
    assertion = re.search(r"expected .*?got|beta: |experience\.json: ", out, re.S) is not None
    broken = re.search(r"could not load spec|attempt to |Unable to require|Syntax|syntax error", out) is not None
    verdict = (
        "killed"
        if failed > 0 and assertion and not broken
        else ("SURVIVED" if failed == 0 else "ERROR (not an assertion)")
    )
    cases = [l.split(" :: ", 1)[1] for l in out.splitlines() if l.startswith("FAIL ") and " :: " in l]
    print(f"{name}: {verdict} ({m.group(0) if m else 'no result line'}) {path} -> {spec}")
    for c in cases[:4]:
        print(f"    FAIL {c}")
    detail = [l.strip() for l in out.splitlines() if l.startswith("     ")]
    for d in detail[:1]:
        print(f"      {d[:200]}")
