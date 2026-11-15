# d0333 prototype: the three post-finish lists take the raft's own spend.md.
# Usage: python3 -I fix.py <checkout> [<mutant>]   (mutants M1..M9, see MUTANTS below)
import sys

root = sys.argv[1]
mutant = sys.argv[2] if len(sys.argv) > 2 else ""

A = '''			name == "trace.md"
			or name == `{raftId}.md`
			or string.match(name, "^review%-%d+%.md$") ~= nil'''
A_FIX = '''			name == "trace.md"
			or name == "spend.md" -- d0333: every `./zn commit` rewrites the raft's snapshot
			or name == `{raftId}.md`
			or string.match(name, "^review%-%d+%.md$") ~= nil'''
B = '''		if
			name == `{raftId}.md`
			or string.match(name, "^final%-review%-%d+%.md$") ~= nil'''
B_FIX = '''		if
			name == `{raftId}.md`
			or name == "spend.md" -- d0333
			or string.match(name, "^final%-review%-%d+%.md$") ~= nil'''
SPEND_D = '''	if string.find(path, "/spend%.d/", 1, false) ~= nil then
		return true
	end
'''
ANY_SPEND = SPEND_D + '''	if string.find(path, "/spend%.md$") ~= nil then
		return true
	end
'''

MUTANTS = {
    "M1": "layergit.isPostFinishPath left as it is",
    "M2": "trace's isTrackerFileOf left as it is",
    "M3": "trace's isAllowedAfterTrace left as it is",
    "M4": "layergit takes any path ending /spend.md",
    "M5": "trace's isTrackerFileOf takes any path ending /spend.md",
    "M6": "layergit also takes the raft's harvest.md",
    "M7": "trace's isAllowedAfterTrace also takes trace's pre-table set (issue documents)",
    "M8": "trace's isAllowedAfterTrace takes any path ending /spend.md",
    "M9": "trace's isTrackerFileOf also takes the raft's harvest.md",
}
if mutant and mutant not in MUTANTS:
    sys.exit("unknown mutant " + mutant)


def once(s, old, new, what):
    if s.count(old) != 1:
        sys.exit(f"{what}: anchor found {s.count(old)} times")
    return s.replace(old, new)


# layergit
p = root + "/z-nile/engine/layergit.luau"
s = open(p).read()
if mutant == "M4":
    head, tail = s.split("function layergit.isPostFinishPath", 1)
    tail = once(tail, SPEND_D, ANY_SPEND, "layergit spend.d")
    s = head + "function layergit.isPostFinishPath" + tail
elif mutant == "M6":
    s = once(s, A, A_FIX.replace('or name == "spend.md"', 'or name == "spend.md"\n\t\t\tor name == "harvest.md"'), "layergit A")
elif mutant != "M1":
    s = once(s, A, A_FIX, "layergit A")
open(p, "w").write(s)

# trace
p = root + "/z-nile/engine/trace.luau"
s = open(p).read()
pre, rest = s.split("local function isTrackerFileOf", 1)
first, second = rest.split("local function isAllowedAfterTrace", 1)
if mutant == "M5":
    first = once(first, SPEND_D, ANY_SPEND, "trace first spend.d")
elif mutant == "M9":
    first = once(first, A, A_FIX.replace('or name == "spend.md"', 'or name == "spend.md"\n\t\t\tor name == "harvest.md"'), "trace A")
elif mutant != "M2":
    first = once(first, A, A_FIX, "trace A")
if mutant == "M8":
    second = second.replace(SPEND_D, ANY_SPEND, 1)
elif mutant == "M7":
    second = once(second, B, B_FIX.replace('or name == "spend.md" -- d0333', 'or name == "spend.md" -- d0333\n\t\t\tor string.match(name, "^review%-%d+%.md$") ~= nil'), "trace B")
    # and the issue documents, as the pre-table rule takes them
    second = second.replace("	return false\nend\n", '	if string.find(path, "/issues/active/[fdc]%d%d%d%d/[fdc]%d%d%d%d%.md$") ~= nil then\n\t\treturn true\n\tend\n\treturn false\nend\n', 1)
elif mutant != "M3":
    second = once(second, B, B_FIX, "trace B")
open(p, "w").write(pre + "local function isTrackerFileOf" + first + "local function isAllowedAfterTrace" + second)
