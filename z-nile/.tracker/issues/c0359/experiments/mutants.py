# c0359 mutation check (z-design step 4): each row of the Rules and mutants table, applied to the prototype in a clone
# under $TMPDIR (experiments/clone.sh, then `git apply experiments/prototype.patch` and this item's acceptance/ copied
# in), must turn its named spec case red on an assertion ("expected ..."), not a syntax or require error, and the
# clone is put back after each. Usage: ./zn run --time 3600 -- python3 z-nile/.tracker/issues/c0359/experiments/mutants.py <clone> [M-id...]
# (about 8 minutes on 2026-11-15: the gate spec takes 35 s a run)
import os, pathlib, re, subprocess, sys
CLONE = pathlib.Path(sys.argv[1])
if not str(CLONE).startswith(os.environ.get("TMPDIR", "/tmp").rstrip("/")) and not str(CLONE).startswith("/var/folders"):
    sys.exit(f"not a clone under $TMPDIR: {CLONE}")
ONLY = set(sys.argv[2:])
HERE = pathlib.Path(__file__).resolve().parent
A = ".tracker/issues/c0359/acceptance"
WF, RS, CK = ".github/workflows/static.yml", ".github/rulesets/static.json", "z-nile/check.sh"
DP, DR = "z-nile/engine/dispatch.luau", "z-nile/engine/dispatcher.luau"
DEPLOY = "z-nile/tests/acceptance/c0172/deploy.spec.luau"
# (id, file, old, new, spec, case prefix); old must occur exactly once
M = [
    ("M1", WF, "    types: [opened, synchronize, reopened, ready_for_review]\n",
     "    types: [opened, synchronize, reopened, ready_for_review]\n    paths-ignore: ['**/.tracker/**']\n", "workflow", "static.yml is one job"),
    ("M2", WF, "    runs-on: ubuntu-latest\n", "    if: github.event.pull_request.draft == false\n    runs-on: ubuntu-latest\n", "workflow", "static.yml is one job"),
    ("M3", WF, "      - run: z-nile/check.sh --lint\n", "      - run: z-nile/check.sh --static\n", "workflow", "its steps"),
    ("M4", WF, "      - run: z-nile/check.sh --lint\n", "      - run: z-nile/check.sh --lint\n        env:\n          KEY: ${{ secrets.ROBLOX_API_KEY }}\n", "workflow", "it reads no secret"),
    ("M5", RS, '"integration_id": 15368', '"integration_id": 1', "ruleset", "the ruleset requires"),
    ("M6", RS, '"bypass_mode": "always"', '"bypass_mode": "pull_request"', "ruleset", "the ruleset requires"),
    ("M7", RS, '"strict_required_status_checks_policy": false', '"strict_required_status_checks_policy": true', "ruleset", "the ruleset requires"),
    ("M8", WF, "jobs:\n  static:\n", "jobs:\n  lint:\n", "ruleset", "the required context is"),
    ("M9", DP, 'string.match(name, "%.luau?$")', 'string.match(name, "%.luau$")', "lintable", "a Lua or Luau source"),
    ("M10", DP, 'local name = string.lower(string.match(path, "[^/]+$") or path)', 'local name = string.match(path, "[^/]+$") or path', "lintable", "a Lua or Luau source"),
    ("M11", DP, '\t\tor string.match(name, "%.toml$") ~= nil\n', "", "lintable", "a TOML, YAML or dotfile"),
    ("M12", DP, 'string.match(name, "%.luau?$")', 'string.match(name, "%.luau?")', "lintable", "documents, scripts"),
    ("M13", CK, "if [[ $mode == lint ]]; then\n  lint_stages\n", "if [[ $mode == lint ]]; then\n  par_start \"format (stylua --check)\" stylua --check \"${LUAU_DIRS[@]}\"\n", "lint", "a lint warning alone"),
    ("M14", CK, "if [[ $mode == affected || $mode == static ]] && [[ ${#wanted[@]} -eq 0 ]]; then",
     "if [[ $mode == affected || $mode == static || $mode == lint ]] && [[ ${#wanted[@]} -eq 0 ]]; then", "lint", "it is never narrowed"),
    ("M15", CK, "if [[ $mode == lint ]]; then\n  lint_stages\n",
     "if [[ $mode == lint ]]; then\n  for h in ${srcs[@]+\"${srcs[@]}\"}; do (cd \"$h\" && rojo sourcemap default.project.json -o sourcemap.json); done\n  lint_stages\n", "lint", "it writes nothing outside .cache"),
    ("M16", CK, "if [[ -n $plan && $mode == lint ]]; then", "if false; then", "lint", "--plan prints the two stages"),
    ("M17", CK, "if [[ $mode == lint ]]; then\n  lint_stages\n  par_wait || exit 1\n",
     "if [[ $mode == lint ]]; then\n  stylua --check \"${LUAU_DIRS[@]}\" && selene --quiet \"${LUAU_DIRS[@]}\" || exit 1\n", "lint", "both stages run and report"),
    ("M18", DR, "\tlocal root = ctx.mainRoot()\n\tlocal okD, names =", "\tdo\n\t\treturn nil\n\tend\n\tlocal root = ctx.mainRoot()\n\tlocal okD, names =", "gate", "a prep PR whose merge fails the format stage"),
    ("M19", DR, "\t-- c0359: last, the gate's own format and lint stages on what the merge would make\n",
     "\t-- c0359: last, the gate's own format and lint stages on what the merge would make\n\tif gateName ~= \"prep\" then\n\t\treturn nil\n\tend\n", "gate", "a rafting PR whose merge fails"),
    ("M20", DR, "\tif not lintable then\n\t\treturn nil\n\tend\n", "", "gate", "a PR that changes no path"),
    ("M21", DR, 'git(root, { "archive", "--format=tar", "-o", tar, tree :: string })', 'git(root, { "archive", "--format=tar", "-o", tar, ref })', "gate", "the stages read the merge"),
    ("M22", DR, "\tlocal said = table.concat(lines, \"\\n\")\n", "\tlocal said = \"\"\n", "gate", "a prep PR whose merge fails the format stage"),
    ("M23", DR, "\t\tif fs.isDir(dir) then\n\t\t\tpcall(fs.removeDir, dir)\n\t\tend\n\t\treturn why\n", "\t\treturn why\n", "gate", "no judgement leaves"),
    ("M24", DR, "\tlocal own: { [string]: boolean } = if gateName == \"prep\" then { [id] = true } else {}\n",
     "\tdo\n\t\tlocal early = dispatcher.lintMerge(ctx, pr.number, main, ref, if okBase then base else nil)\n\t\tif early then\n\t\t\treturn early\n\t\tend\n\tend\n\tlocal own: { [string]: boolean } = if gateName == \"prep\" then { [id] = true } else {}\n", "gate", "the stages run only after the shape judgement"),
]
# design review 001's answers (F3, F4, F5)
M += [
    ("M25", CK, "[[ -n $plan ]] || [[ $mode == lint ]] || ./zn reap --auto || true\n", "[[ -n $plan ]] || ./zn reap --auto || true\n", "lint", "it reaps nothing"),
    ("M26", DP, "\t\telseif\n\t\t\tnot pr.green and carries\n\t\tthen `the {name} PR #{pr.number} waits for green CI, and for a human: {carries}`\n", "", "gate", "a red static check stops the gate"),
    ("M27", CK, '  par_start "settings (none under .tracker/)" tracker_settings\n', "", "lint", "a format or lint setting under a .tracker/ folder"),
    ("M28", CK, '  par_start "settings (none under .tracker/)" tracker_settings\n', "", "gate", "a format setting in a prep PR's folder"),
]
# narrowing mutants of the promoted c0172 deploy spec (narrow.py, AC6): each must make narrow.py exit 1
N = [
    ("N1", "\t\tt.expect(wf.jobs.gate).toBe(nil)\n", ""),  # a deleted assertion in another case
    ("N2", "\t\tlocal wf = load()\n\t\tlocal names = {}\n", "\t\tlocal wf = load() -- joined\n\t\tlocal names = {}\n"),  # an edited line
    ("N3", '\tit("the gate workflow, the board workflow and ci-verify are absent", function()\n',
     '\tit("the gate workflow, the board workflow and ci-verify are absent", function()\n\t\tdo return end\n'),  # an added line
    ("N4", '\t\tt.expect(names).toEqual({ "deploy.yml", "static.yml" })\n', '\t\tt.expect(names).toEqual({ "deploy.yml", "static.yml", "x.yml" })\n'),
]

def specs(spec):
    r = subprocess.run(["bash", str(HERE / "specs.sh"), str(CLONE), f"{A}/{spec}.spec.luau"], capture_output=True, text=True)
    return r.stdout + r.stderr

def killed(out, prefix):
    lines = out.split("\n")
    for i, line in enumerate(lines):
        if line.startswith("FAIL ") and " :: " + prefix in line:
            return "expected" in (lines[i + 1] if i + 1 < len(lines) else ""), lines[i + 1].strip() if i + 1 < len(lines) else ""
    return False, "the case did not fail"

bad = []
for mid, rel, old, new, spec, prefix in M:
    if ONLY and mid not in ONLY:
        continue
    path = CLONE / rel
    text = path.read_text()
    if text.count(old) != 1:
        bad.append(f"{mid}: its anchor occurs {text.count(old)} times in {rel}"); continue
    path.write_text(text.replace(old, new))
    try:
        ok, why = killed(specs(spec), prefix)
    finally:
        path.write_text(text)
    print(f"{mid} {'killed' if ok else 'SURVIVED'}: {spec} :: {prefix} ({why[:160]})")
    if not ok:
        bad.append(mid)
# narrow.py against the clone's own main as origin (the base) with the patched file
subprocess.run(["git", "-C", str(CLONE), "remote", "remove", "origin"], capture_output=True)
subprocess.run(["git", "-C", str(CLONE), "remote", "add", "origin", str(CLONE)], check=True)
def narrow():
    r = subprocess.run(["python3", str(CLONE / "z-nile" / A / "narrow.py"), str(CLONE)], capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip()
code, said = narrow()
print(f"N0 (the reviewed override): exit {code}: {said[:160]}")
if code != 0:
    bad.append("N0")
for nid, old, new in N:
    if ONLY and nid not in ONLY:
        continue
    path = CLONE / DEPLOY
    text = path.read_text()
    if text.count(old) != 1:
        bad.append(f"{nid}: its anchor occurs {text.count(old)} times"); continue
    path.write_text(text.replace(old, new))
    try:
        code, said = narrow()
    finally:
        path.write_text(text)
    ok = code == 1 and "differs from its base" in said
    print(f"{nid} {'killed' if ok else 'SURVIVED'}: narrow.py exit {code}: {said[:120]}")
    if not ok:
        bad.append(nid)
subprocess.run(["git", "-C", str(CLONE), "remote", "remove", "origin"], capture_output=True)
print("all mutants killed" if not bad else "not killed: " + ", ".join(bad))
sys.exit(1 if bad else 0)
