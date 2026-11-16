#!/usr/bin/env python3
# c0156 prep mutation check. Usage: python3 mutants.py <clone>
# <clone> is a separate clone of the repository under the temp folder (never the real checkout) with the prototype
# applied (experiments/prototype.patch) and this issue's acceptance/ folder in place under
# z-nile/.tracker/issues/c0156/acceptance. Each MUTANT weakens the pin rule or a pinned file the way a careless edit
# could, and the specs named for it must fail on an ASSERTION (not a load error); each VARIANT is a correct change
# (line endings, indentation, trailing blanks) and every spec must stay green. Every run is time-bounded and its whole
# process group is killed at the limit; files are restored after every run.
import os, pathlib, signal, subprocess, sys, tempfile

if len(sys.argv) < 2:
    sys.exit("usage: mutants.py <clone under the temp folder> [<id>...]")
ONLY = set(sys.argv[2:])
root = pathlib.Path(sys.argv[1]).resolve()
tmp = pathlib.Path(tempfile.gettempdir()).resolve()
if tmp not in root.parents or not (root / ".git").is_dir() or (root / ".worktree").exists():
    sys.exit(f"{root}: not a separate clone under {tmp}")
here = pathlib.Path(__file__).resolve().parent
real_git = subprocess.run(
    ["git", "-C", str(here), "rev-parse", "--path-format=absolute", "--git-common-dir"],
    capture_output=True, text=True, check=True,
).stdout.strip()
env = dict(os.environ)
env["PICKMAN_FENCE_REAL_GIT"] = (env.get("PICKMAN_FENCE_REAL_GIT", "") + ":" if env.get("PICKMAN_FENCE_REAL_GIT") else "") + real_git

PIN = "z-nile/tests/lib/pin.luau"
NARROWED_SPEC = "pickman/tests/acceptance/c0103/narrowed.spec.luau"
GOLDEN_SPEC = "pickman/tests/acceptance/c0128/golden.spec.luau"
KEYS = "pickman/tests/acceptance/f0014/keys.spec.luau"
A = "pickman/tests/acceptance/f0024/adapter.spec.luau"
B = "pickman/tests/acceptance/f0026/adapters.spec.luau"
# the unit spec, found from where this script lives: the backlog folder before ./zn ready, active/ after it
zn_dir = next((d for d in here.parents if d.name == "z-nile"), None)
if zn_dir is None:
    sys.exit(f"{here}: not under a z-nile/ folder")
UNIT_REL = (here.parent / "acceptance" / "pin.spec.luau").relative_to(zn_dir)
if not (root / "z-nile" / UNIT_REL).is_file():
    sys.exit(f"{root / 'z-nile' / UNIT_REL}: the clone has no copy of the acceptance spec (is this issue's folder in the clone, at the same place?)")
UNIT = ("z-nile", [str(UNIT_REL)])
def script(name):  # a check.sh-only script of this issue's acceptance folder, run from z-nile/ with the clone's top
    return ("z-nile", [str(UNIT_REL.parent / name)], "script")
KILLS, CONSUMERS, RECORD_CHECK = script("kills.luau"), script("consumers.luau"), script("record.luau")
NARROWED = ("pickman", ["tests/acceptance/c0103/narrowed.spec.luau"])
GOLDEN = ("pickman", ["tests/acceptance/c0128/golden.spec.luau"])
BOTH = ("pickman", ["tests/acceptance/c0103/narrowed.spec.luau", "tests/acceptance/c0128/golden.spec.luau"])

def sub(old, new):
    def edit(src):
        if src.count(old) != 1:
            raise ValueError(f"anchor found {src.count(old)} times: {old!r}")
        return src.replace(old, new)
    return edit

def crlf(src):
    return src.replace("\r\n", "\n").replace("\n", "\r\n")

def spaces(src):  # every leading tab becomes four spaces
    return "\n".join(l[: len(l) - len(l.lstrip("\t"))].replace("\t", "    ") + l.lstrip("\t") for l in src.split("\n"))

def trailing(src):
    return src.replace("\n", " \t\n")

# (id, path, edit, (home, specs))
MUTANTS = [
    # the rule (pin.spec)
    ("collapse-newlines", PIN, sub('"[ \\t]+", " "', '"%s+", " "'), UNIT),
    ("squeeze-blank-lines", PIN, sub('\ttext = string.gsub(text, " \\n", "\\n")\n', '\ttext = string.gsub(text, " \\n", "\\n")\n\ttext = string.gsub(text, "\\n\\n+", "\\n")\n'), UNIT),
    ("tabs-not-collapsed", PIN, sub('"[ \\t]+", " "', '"[ ]+", " "'), UNIT),
    ("keep-trailing-space", PIN, sub('\ttext = string.gsub(text, " \\n", "\\n")\n', ''), UNIT),
    ("lone-cr-kept", PIN, sub('"\\r\\n?"', '"\\r\\n"'), UNIT),
    ("cr-dropped", PIN, sub('text = string.gsub(text, "\\r\\n?", "\\n")', 'text = string.gsub(text, "\\r", "")'), UNIT),
    ("no-id-mask", PIN, sub('\ttext = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")\n', ''), UNIT),
    ("id-mask-no-right-frontier", PIN, sub('%d+%f[^%w_]', '%d+'), UNIT),
    ("id-mask-no-left-frontier", PIN, sub('"%f[%w_][fdcR]%d+', '"[fdcR]%d+'), UNIT),
    ("id-mask-any-letter", PIN, sub('[fdcR]%d+', '%a%d+'), UNIT),
    ("vf-line-break", PIN, sub('"\\r\\n?"', '"[\\r\\v\\f]\\n?"'), UNIT),
    ("vf-collapsed", PIN, sub('"[ \\t]+", " "', '"[ \\t\\v\\f]+", " "'), UNIT),
    ("no-comma-rule", PIN, sub('\ttext = string.gsub(text, ",( ?\\n?[ ]?)}", "%1}")\n', ''), UNIT),
    ("comma-rule-any-blank-run", PIN, sub('",( ?\\n?[ ]?)}", "%1}"', '",%s*}", "}"'), UNIT),
    ("comma-before-any-newline", PIN, sub('",( ?\\n?[ ]?)}", "%1}"', '",( ?\\n)", "%1"'), UNIT),
    ("no-leading-trim", PIN, sub('\ttext = string.gsub(text, "^[%s]+", "")\n', ''), UNIT),
    ("no-trailing-trim", PIN, sub('\ttext = string.gsub(text, "[%s]+$", "")\n', ''), UNIT),
    ("digest-of-raw-text", PIN, sub('serde.hash("sha256", pin.normalise(text))', 'serde.hash("sha256", text)'), UNIT),
    ("digest-sha1", PIN, sub('serde.hash("sha256"', 'serde.hash("sha1"'), UNIT),
    ("joined-raw-text", PIN, sub('local src = pin.normalise(text)\n\tlocal needle = pin.normalise(comment)', 'local src = text\n\tlocal needle = pin.normalise(comment)'), UNIT),
    ("joined-raw-comment", PIN, sub('local needle = pin.normalise(comment)', 'local needle = comment'), UNIT),
    ("joined-silent-miss", PIN, sub('error(`no line ends in the comment "{needle}"`, 2)', 'return src'), UNIT),
    ("joined-blank-line-ok", PIN, sub('if string.sub(rest, 1, 1) == "\\n" then', 'if false then'), UNIT),
    ("joined-no-space", PIN, sub('.. " " .. (string.gsub(rest', '.. (string.gsub(rest'), UNIT),
    ("joined-keeps-indent", PIN, sub('(string.gsub(rest, "^ ", "", 1))', 'rest'), UNIT),
    ("joined-second-occurrence", PIN, sub('string.find(src, needle .. "\\n", 1, true)', 'string.find(src, needle .. "\\n", #needle + 2, true)'), UNIT),
    ("without-silent-miss", PIN, sub('error(`the text has no "{needle}" to delete`, 2)', 'return src'), UNIT),
    ("without-repeated-ok", PIN, sub('if string.find(src, needle, to + 1, true) ~= nil then', 'if false then'), UNIT),
    ("without-raw-text", PIN, sub('local src = pin.normalise(text)\n\tlocal needle = pin.normalise(piece)', 'local src = text\n\tlocal needle = pin.normalise(piece)'), UNIT),
    ("without-raw-piece", PIN, sub('local needle = pin.normalise(piece)', 'local needle = piece'), UNIT),
    # the pinned files (the promoted pin specs)
    ("join-f0014-header-swallows-require", KEYS, sub("can be added without a red main.\nlocal Movement", "can be added without a red main. local Movement"), NARROWED),
    ("join-f0014-title", KEYS, sub("by Enum.KeyCode name.\n-- Narrowed", "by Enum.KeyCode name. -- Narrowed"), NARROWED),
    ("delete-f0014-assertion", KEYS, sub("\t\tt.expect(n >= 4).toBe(true)\n", ""), NARROWED),
    ("join-f0026-reads-comment", B, sub("each at page sizes 10 and 50\n", "each at page sizes 10 and 50 "), GOLDEN),
    ("join-f0026-companion-comment", B, sub("-- c0128: the per-player companion store is still read\n", "-- c0128: the per-player companion store is still read "), GOLDEN),
    ("join-f0024-perplayer-comment", A, sub("only d0124's top-N list of runs\n", "only d0124's top-N list of runs "), GOLDEN),
    ("delete-f0024-assertion", A, sub("\t\tt.expect(updates).toBe(6)\n", ""), GOLDEN),
    ("delete-f0026-assertion", B, sub("\t\tt.expect(#w.reads).toBe(0)\n", ""), GOLDEN),
]
# a pin whose comparison was weakened: its own mutant cases must go red (the pin spec is edited, not the pinned file)
MUTANTS += [
    ("weak-compare-narrowed", NARROWED_SPEC, sub("return pin.digest(text) == DIGEST", "return #pin.digest(text) == #DIGEST"), NARROWED),
    ("always-exactly-narrowed", NARROWED_SPEC, sub("return pin.digest(text) == DIGEST", "return true"), NARROWED),
    ("weak-compare-f0024", GOLDEN_SPEC, sub("return pin.digest(text) == D24", "return #pin.digest(text) == #D24"), GOLDEN),
    ("weak-compare-f0026", GOLDEN_SPEC, sub("return pin.digest(text) == D26", "return #pin.digest(text) == #D26"), GOLDEN),
]
# the check.sh-only scripts (AC2, AC5, AC7): each goes red for the wrong pin, record or script
def cut_case(title):  # drop the `it(` block whose title starts with `title` (up to the next blank-line-separated case)
    def edit(src):
        at = src.find(title)
        if at < 0:
            raise ValueError(f"no case {title!r}")
        start = src.rfind("\n\tit(", 0, at) + 1
        end = src.find("\n\n\tit(", at)
        end = end + 2 if end >= 0 else src.find("\nend)", at) + 1
        return src[:start] + src[end:]
    return edit
def both(*pairs):  # several edits in one mutant: [(path, edit), ...]
    return list(pairs)
WEAK24 = sub("return pin.digest(text) == D24", "return #pin.digest(text) == #D24")
WEAK26 = sub("return pin.digest(text) == D26", "return #pin.digest(text) == #D26")
WEAK_N = sub("return pin.digest(text) == DIGEST", "return #pin.digest(text) == #DIGEST")
RECORD_PY = "pickman/.tracker/rafts/done/R0045/experiments/mutants.py"
KILLS_LUAU = "z-nile/" + str(UNIT_REL.parent / "kills.luau")
MUTANTS += [
    ("kills-weak-f0024-no-mutant-case", both((GOLDEN_SPEC, WEAK24), (GOLDEN_SPEC, cut_case("f0024: a line joined"))), None, KILLS),
    ("kills-weak-f0026-no-mutant-case", both((GOLDEN_SPEC, WEAK26), (GOLDEN_SPEC, cut_case("the review's two joins in f0026"))), None, KILLS),
    ("kills-weak-narrowed-no-mutant-case", both((NARROWED_SPEC, WEAK_N), (NARROWED_SPEC, cut_case("a line joined onto the comment line above it"))), None, KILLS),
    ("kills-pin-reads-the-wrong-file", GOLDEN_SPEC, sub("t.expect(exactly24(fs.readFile(F24))).toBe(true)", "t.expect(exactly24(fs.readFile(F26))).toBe(true)"), KILLS),
    ("kills-counts-a-raise-as-a-kill", both((KILLS_LUAU, sub('if scripted.has(f, "expected true, got false") then', "if true then"))), None, KILLS),
    ("kills-probe-pin-f0024", GOLDEN_SPEC, sub("return pin.digest(text) == D24", 'return string.find(pin.normalise(text), "t.expect(updates).toBe(6)", 1, true) ~= nil and string.find(pin.normalise(text), "top-N list of runs\\n", 1, true) ~= nil'), KILLS),
    ("kills-fixed-mutant-set", KILLS_LUAU, sub("local mutants, unchanged = generated(lf)", "local mutants: { { string } } = {}\n\t\tlocal unchanged = 0"), KILLS),
    ("kills-no-in-place-mutants", KILLS_LUAU, sub('if string.find(line, "%S") then\n\t\t\tlocal edited = perturb(line)', 'if false then\n\t\t\tlocal edited = perturb(line)'), KILLS),
    ("kills-shape-pin", both((GOLDEN_SPEC, sub("return pin.digest(text) == D24", 'return #pin.digest(text) == #D24 and select(2, string.gsub(pin.normalise(text), "\\n", "")) == 373 and select(2, string.gsub(pin.normalise(text), "t%.expect%(", "")) == 44')), (GOLDEN_SPEC, sub("return pin.digest(text) == D26", 'return #pin.digest(text) == #D26 and select(2, string.gsub(pin.normalise(text), "\\n", "")) == 986 and select(2, string.gsub(pin.normalise(text), "t%.expect%(", "")) == 149')), (NARROWED_SPEC, sub("return pin.digest(text) == DIGEST", 'return #pin.digest(text) == #DIGEST and select(2, string.gsub(pin.normalise(text), "\\n", "")) == 40 and select(2, string.gsub(pin.normalise(text), "t%.expect%(", "")) == 5'))), None, KILLS),
    ("kills-unchanged-lines-ignored", KILLS_LUAU, sub("local base = pin.normalise(line)\n", "local base = pin.normalise(line)\n\tif string.find(line, \"^%s*%-%-\") then\n\t\treturn nil\n\tend\n"), KILLS),
    ("consumers-verdict-heads", NARROWED_SPEC, sub("return pin.digest(text) == DIGEST", "return pin.digest(string.sub(text, 1, 10)) == DIGEST"), CONSUMERS),
    ("kills-globals-injected", KILLS_LUAU, sub(", injectGlobals = false })", " })"), KILLS),
    ("digest-recomputed-on-a-changed-file", both((KEYS, sub("\t\t\tt.expect(View.action(key)).toBe(nil)\n", "")), (NARROWED_SPEC, sub('local DIGEST = "ed27eb8bf258d9019129336876becd8133428099b4653d7b6546fcc5db052be6"', 'local DIGEST = "825551fe8d9d98d82cc38461d118bc1abf9c6b75ac9e3cdff4163554574d74b2"'))), None, CONSUMERS),
    ("consumers-pin-keeps-its-own-collapse", NARROWED_SPEC, sub("local DIGEST =", 'local COLLAPSE = string.gsub("a b", "%s+", " ")\nlocal DIGEST ='), CONSUMERS),
    ("consumers-forwarder-missing", "pickman/tests/lib/pin.luau", sub('"../../../z-nile/tests/lib/pin"', '"../../../z-nile/tests/lib/t"'), CONSUMERS),
    ("consumers-forwarder-shadowed", "pickman/tests/lib/pin.luau", sub('return require("../../../z-nile/tests/lib/pin")', '-- return require("../../../z-nile/tests/lib/pin")\nreturn {}'), CONSUMERS),
    ("record-join-entry-is-a-no-op", RECORD_PY, sub("'join-f0014-comment', K, 'can be added without a red main.\\nlocal Movement', 'can be added without a red main. local Movement'", "'join-f0014-comment', K, 'can be added without a red main.\\nlocal Movement', 'can be added without a red main.\\nlocal Movement'"), RECORD_CHECK),
    ("record-guard-no-temp-check", RECORD_PY, sub("tmp not in clone.parents or ", ""), RECORD_CHECK),
    ("record-guard-no-git-dir-check", RECORD_PY, sub("not (clone / '.git').is_dir() or ", ""), RECORD_CHECK),
    ("record-guard-no-worktree-check", RECORD_PY, sub(" or (clone / '.worktree').exists()", ""), RECORD_CHECK),
    ("record-guard-no-name-check", RECORD_PY, sub("root.name != 'pickman' or ", ""), RECORD_CHECK),
    ("record-guard-refuses-everything", RECORD_PY, sub("if root.name != 'pickman'", "if True or root.name != 'pickman'"), RECORD_CHECK),
    ("record-guard-removed", RECORD_PY, sub("    sys.exit(f'{root}: not the pickman home of a separate clone under {tmp}')", "    pass"), RECORD_CHECK),
    ("record-guard-warns-only", RECORD_PY, sub("    sys.exit(f'{root}: not the pickman home of a separate clone under {tmp}')", "    print(f'{root}: not the pickman home of a separate clone under {tmp}', file=sys.stderr)"), RECORD_CHECK),
]
# correct changes: the pins must stay green
VARIANTS = [
    ("crlf-f0014", KEYS, crlf, NARROWED),
    ("crlf-f0026", B, crlf, GOLDEN),
    ("crlf-f0024", A, crlf, GOLDEN),
    ("four-space-indent-f0014", KEYS, spaces, NARROWED),
    ("trailing-blanks-f0026", B, trailing, GOLDEN),
    ("renumbered-ids-f0014", KEYS, sub("f0130 AC5", "f0200 AC5"), NARROWED),
]

def run(target):
    home, args = target[0], target[1]
    if len(target) == 3:  # a check.sh-only script: lune run <script> -- <the clone's top>
        cmd = ["lune", "run", args[0], "--", str(root)]
    else:
        cmd = ["lune", "run", "tests/run", "--"] + args
    p = subprocess.Popen(
        cmd, cwd=root / home, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True,
    )
    try:
        out, _ = p.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        out, _ = p.communicate()
        out += "\nTIMEOUT"
    return out, p.returncode

bad = []
for kind, table in (("mutant", MUTANTS), ("variant", VARIANTS)):
    for name, rel, edit, target in table:
        if ONLY and name not in ONLY:
            continue
        edits = rel if isinstance(rel, list) else [(rel, edit)]
        saved = {}
        problem = None
        try:
            for r, e in edits:
                path = root / r
                saved.setdefault(path, path.read_bytes())
                path.write_bytes(e(path.read_bytes().decode()).encode())
        except (ValueError, FileNotFoundError) as err:
            problem = f"{name}: {err}"
        out, code = ("", 0)
        try:
            if problem is None:
                out, code = run(target)
        finally:
            for path, data in saved.items():
                path.write_bytes(data)
        if problem:
            bad.append(problem)
            continue
        fails = [l for l in out.splitlines() if l.startswith("FAIL ")]
        if "TIMEOUT" in out:
            bad.append(f"{name}: timed out")
        elif kind == "mutant":
            if len(target) == 3:  # a script is killed by its own FAIL line and a non-zero exit
                if code == 0 or not fails:
                    bad.append(f"{name}: survived" if code == 0 else f"{name}: failed without a FAIL line (a crash?)")
                else:
                    print(f"killed {name}: " + " | ".join(l[5:60] for l in fails[:3]))
            elif not fails:
                bad.append(f"{name}: survived")
            elif any("could not load" in l for l in out.splitlines()):
                bad.append(f"{name}: load error")
            else:
                print(f"killed {name}: " + " | ".join(l.split(" :: ", 1)[-1][:48] for l in fails))
        else:
            if fails:
                bad.append(f"{name}: a correct change turned a spec red: {fails[0]}")
            else:
                print(f"green  {name}")
unknown = ONLY - {m[0] for m in MUTANTS + VARIANTS}
if unknown:
    bad.append(f"no such id: {sorted(unknown)}")
print("\n".join(bad) if bad else ("OK" if ONLY else f"ALL {len(MUTANTS)} MUTANTS KILLED ON ASSERTIONS, ALL {len(VARIANTS)} VARIANTS GREEN"))
sys.exit(1 if bad else 0)
