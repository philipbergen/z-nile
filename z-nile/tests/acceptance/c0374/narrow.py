# c0374 AC2: `z-nile/tests/acceptance/c0120/finished.spec.luau` equals its merge base (git merge-base HEAD <origin's
# main, read with git ls-remote>) with exactly the two reviewed c0374 hunks applied, byte for byte (read as bytes), so
# a deleted or added line anywhere else (an assertion of another case, a `--[[`, a `do return end`, a reworded comment)
# is red (lesson zz-test/narrowing-pins-the-whole-file). The hunks are applied by anchored substitution, each anchor's
# count asserted in the base first, so the pin depends on no line number and on no other case's text:
#   (a) the helper `singleQuoted` (and its comment) is inserted before the one `return t.spec("c0120 finished check.sh
#       files still name paths that resolve from their home", function(it)` line;
#   (b) the one loop in the last case, `for _, l in rewrites.literals(fs.readFile(...)) do ... end`, is replaced by
#       the loop that reads the text once, walks its single quotes and skips a bare file name inside them.
# It runs at `./zn finish` and `./zn done`, before the change lands: a base where an anchor's count differs, or that
# already names `singleQuoted`, is not the stale form this was reviewed against, and is red: stop for a re-prep (the
# base is origin's published main read with git ls-remote, so a moved local ref cannot turn the check green).
# After c0374 lands the merge base holds the change, so a later `./zn check c0374` is red by design (as c0302's and
# c0304's `narrow.py`). It checks this file only; that no other file changes is the code review's.
# Usage: python3 narrow.py <checkout> [<file to judge instead of the checkout's>]
# (the second argument is for prep's mutation check only: check.sh never passes it).
import pathlib, subprocess, sys

R = pathlib.Path(sys.argv[1])
F = "z-nile/tests/acceptance/c0120/finished.spec.luau"


def git(*a):
    return subprocess.run(["git", "-C", str(R), *a], capture_output=True, check=True).stdout


def fail(msg):
    print(msg)
    sys.exit(1)


try:
    tip = git("ls-remote", "origin", "refs/heads/main").decode().split()[0]
except (subprocess.CalledProcessError, IndexError):
    fail("cannot read origin's main with git ls-remote (this check needs the network at finish)")
if subprocess.run(["git", "-C", str(R), "cat-file", "-e", tip + "^{commit}"], capture_output=True).returncode != 0:
    fail(f"origin's main {tip[:8]} is not fetched: fetch origin main first")
MB = git("merge-base", "HEAD", tip).decode().strip()
base = git("show", f"{MB}:{F}")
now = (pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else R / F).read_bytes()

A_AT = b'return t.spec("c0120 finished check.sh files still name paths that resolve from their home", function(it)\n'
HELPER = b'-- c0374: the bytes of `text` inside single quotes, as `mask[line][column]` (a line and column are the scanner\'s: lines\n-- split at "\\n", columns are bytes in the line). rewrites.literals reads a word in single-quoted text as a path\n-- (it tracks only double quotes), though a finished check passes such text to its own helpers (`vocabulary`, `cases`)\n-- and to `bash -c`. The walk keeps a stack of quoting contexts, so `\'"\'"\'`, an escaped quote, a comment and the quotes\n-- inside `$( )` are read as the shell reads them; it returns nil when the text ends inside a quote or a `$(`, and the\n-- caller then fails closed. One `for` over the bytes, so it always ends.\nlocal function singleQuoted(text: string): { [number]: { [number]: boolean } }?\n\tlocal mask: { [number]: { [number]: boolean } } = {}\n\tlocal stack: { string } = { "normal" } -- "normal", "double", "single", or "paren" (a `$(`, closed by `)`)\n\tlocal line, col, skip, comment = 1, 0, false, false\n\tlocal prev = "\\n"\n\tfor i = 1, #text do\n\t\tlocal c = string.sub(text, i, i)\n\t\tcol += 1\n\t\tif c == "\\n" then\n\t\t\tline += 1\n\t\t\tcol = 0\n\t\t\tcomment = false\n\t\t\tskip = false\n\t\telseif skip then\n\t\t\tskip = false\n\t\telseif not comment then -- a comment runs to the end of its line\n\t\t\tlocal top = stack[#stack]\n\t\t\tif top == "single" then\n\t\t\t\tif c == "\'" then\n\t\t\t\t\ttable.remove(stack)\n\t\t\t\telse\n\t\t\t\t\tmask[line] = mask[line] or {}\n\t\t\t\t\tmask[line][col] = true\n\t\t\t\tend\n\t\t\telseif c == "\\\\" then\n\t\t\t\tskip = true\n\t\t\telseif c == "\'" then\n\t\t\t\tif top ~= "double" then\n\t\t\t\t\ttable.insert(stack, "single")\n\t\t\t\tend\n\t\t\telseif c == \'"\' then\n\t\t\t\tif top == "double" then\n\t\t\t\t\ttable.remove(stack)\n\t\t\t\telse\n\t\t\t\t\ttable.insert(stack, "double")\n\t\t\t\tend\n\t\t\telseif c == "(" and prev == "$" then\n\t\t\t\ttable.insert(stack, "paren")\n\t\t\telseif c == ")" and top == "paren" then\n\t\t\t\ttable.remove(stack)\n\t\t\telseif c == "#" and top ~= "double" and string.find(prev, "^[%s;|&(]$") then\n\t\t\t\tcomment = true\n\t\t\tend\n\t\tend\n\t\tprev = c\n\tend\n\tif #stack ~= 1 then\n\t\treturn nil\n\tend\n\treturn mask\nend\n\n'
OLD_LOOP = b'\t\t\t\t\t\t\t\tfor _, l in rewrites.literals(fs.readFile(`{TOP}/{file}`)) do\n\t\t\t\t\t\t\t\t\tlocal from = if l.dir == "" then home else `{home}/{l.dir}`\n\t\t\t\t\t\t\t\t\tif not world.now(`{from}/{l.path}`) and world.before(l.dir .. l.path) then\n\t\t\t\t\t\t\t\t\t\ttable.insert(bad, `{file}: {l.word} (from {home})`)\n\t\t\t\t\t\t\t\t\tend\n'
NEW_LOOP = b'\t\t\t\t\t\t\t\tlocal text = fs.readFile(`{TOP}/{file}`)\n\t\t\t\t\t\t\t\tlocal single = singleQuoted(text)\n\t\t\t\t\t\t\t\tif not single then\n\t\t\t\t\t\t\t\t\ttable.insert(\n\t\t\t\t\t\t\t\t\t\tbad,\n\t\t\t\t\t\t\t\t\t\t`{file}: its quotes do not balance, so single-quoted text is unknown`\n\t\t\t\t\t\t\t\t\t)\n\t\t\t\t\t\t\t\tend\n\t\t\t\t\t\t\t\tfor _, l in rewrites.literals(text) do\n\t\t\t\t\t\t\t\t\tlocal from = if l.dir == "" then home else `{home}/{l.dir}`\n\t\t\t\t\t\t\t\t\t-- c0374: a file named alone (`./zn`) inside single quotes is a message, a case\'s name or\n\t\t\t\t\t\t\t\t\t-- the script of a `bash -c`, as the scanner already reads it inside double quotes\n\t\t\t\t\t\t\t\t\tlocal message = single ~= nil\n\t\t\t\t\t\t\t\t\t\tand not string.find(l.path, "/", 1, true)\n\t\t\t\t\t\t\t\t\t\tand (single[l.line] or {})[l.first] == true\n\t\t\t\t\t\t\t\t\tif\n\t\t\t\t\t\t\t\t\t\tnot message\n\t\t\t\t\t\t\t\t\t\tand not world.now(`{from}/{l.path}`)\n\t\t\t\t\t\t\t\t\t\tand world.before(l.dir .. l.path)\n\t\t\t\t\t\t\t\t\tthen\n\t\t\t\t\t\t\t\t\t\ttable.insert(bad, `{file}: {l.word} (from {home})`)\n\t\t\t\t\t\t\t\t\tend\n'

stale = []
for what, needle in (("(a) the t.spec line", A_AT), ("(b) the literals loop", OLD_LOOP)):
    if base.count(needle) != 1:
        stale.append(f"{what} occurs {base.count(needle)} times, expected 1")
if b"singleQuoted" in base:
    stale.append("the base already names singleQuoted")
if stale:
    fail(f"{F}: the base {MB[:8]} is not the stale form c0374 was reviewed against ({'; '.join(stale)}): this check"
         " runs at finish, before the change lands; stop for a re-prep")

expected = base.replace(A_AT, HELPER + A_AT).replace(OLD_LOOP, NEW_LOOP)
if now != expected:
    a, b = expected.split(b"\n"), now.split(b"\n")
    i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
    want = a[i].decode(errors="replace") if i < len(a) else "<end of file>"
    got = b[i].decode(errors="replace") if i < len(b) else "<end of file>"
    fail(f"{F}: differs from its merge base {MB[:8]} with exactly the two c0374 hunks, first at line {i + 1}:\n"
         f"  expected: {want}\n  found:    {got}\n(apply experiments/prototype.patch exactly; if the base moved, stop for a re-prep)")
print(f"{F}: the base {MB[:8]} with exactly the two c0374 hunks")
