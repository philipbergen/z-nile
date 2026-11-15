--!strict
-- c0230 AC5, checked once before `./zn done` (check.sh runs it only while the sequestered folder exists; it has no
-- `.spec.luau` name, so it is never a spec): the rewritten zz-test lesson says the rule in the words the design gives,
-- keeps both sources, and is short (its body at most 1,200 bytes, c0181's cap for a partly enforced lesson). Run from
-- z-nile's home. Prints one line per check; exit 1 on a failure.
local fs = require("@lune/fs")
local process = require("@lune/process")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local LESSON = "z-nile/skills/zz-test/lessons/specs-never-burn-real-resources.md"
local text = fs.readFile(`{root}/{LESSON}`)

local failed = 0
local function expect(name: string, ok: boolean, why: string?)
	print(`{if ok then "ok  " else "FAIL"} {name}{if not ok and why then `: {why}` else ""}`)
	if not ok then
		failed += 1
	end
end

local front, body = string.match(text, "^%-%-%-\n(.-)\n%-%-%-\n(.*)$")
expect("the lesson has frontmatter", front ~= nil)
local fields: { [string]: string } = {}
for line in string.gmatch(front or "", "[^\n]+") do
	local k, v = string.match(line, "^([%w_]+): (.*)$")
	if k and v then
		fields[k :: string] = v :: string
	end
end

expect(
	"title",
	fields.title == "A promoted spec is fast and cheap; a proof that needs real work is a check.sh-only script run once",
	fields.title
)
expect("when", fields.when == "design", fields.when)
expect(
	"check",
	fields.check
		== "Does this spec burn CPU, wait for seconds or write thousands of files, and if it must, is that proof a check.sh-only script (no .spec.luau name, gated on the sequestered folder, under `ulimit -t`) run once and never promoted, with the suite keeping the rule through a stand-in plus one cheap unmocked observation?",
	fields.check
)
for _, tag in { "specs", "speed", "cpu", "files", "stand-ins", "check-sh", "promotion" } do
	expect(`tag {tag}`, string.find(fields.tags or "", tag, 1, true) ~= nil, fields.tags)
end
local b = body or ""
for _, sentence in
	{
		"A test runs on a shared machine at every gate, forever, so it is fast and cheap: it burns no CPU, sleeps no seconds and writes no thousands of files.",
		'"You can use it to prove that your implementation works and then it gets removed. I\'m not running that. Make a lesson, fast tests are important"',
		"c0191's rounds 1 to 5 shipped perl spinners that burned a core on every full gate (c0230).",
		'a stand-in alone passed "set the limit in a subshell"',
		"Split by cost, not by file (zz-test/proofs-hold-only-the-cases-that-wait).",
		"The runner's `over budget:` lines show a file's wall and CPU, c0178's `fixtures:` line its files and processes.",
	}
do
	expect(`says: {string.sub(sentence, 1, 60)}`, string.find(b, sentence, 1, true) ~= nil)
end
expect(`the body is at most 1200 bytes ({#b})`, #b <= 1200)

process.exit(if failed == 0 then 0 else 1)
