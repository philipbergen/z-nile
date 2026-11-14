--!strict
-- c0161 AC3: a raft's carried move (`status <R-id> prepared`) asks the same of every `preparing` issue it takes as
-- `status <id> prepared` asks of one issue: an approving round in the member's own folder that quotes its record. The
-- old prep's `new raft` over `new` issues is no exception (a round only in the raft's folder does not stand in for the
-- member's), and an issue that is already prepared is taken as it is. Uses a prepared issue with no review (work that
-- predates the rule). Fixture under .cache/c0161-review-raft (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local f: trackerfix.Fixture
local wt = ""

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tr(args: { string }): fixture.Result
	return trackerfix.tr(f, wt, args)
end
local function trOk(args: { string }): string
	return trackerfix.trOk(f, wt, args)
end
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function write(path: string, text: string)
	fs.writeFile(path, text)
end
local function setLine(path: string, key: string, value: string)
	local text = fs.readFile(path)
	local s, e = string.find(text, `\n{key}:[^\n]*\n`)
	assert(s and e, `{path} has no {key}:`)
	write(path, string.sub(text, 1, s) .. `{key}: {value}\n` .. string.sub(text, e + 1))
end
local function record(id: string): string
	return trOk({ "design-record", id })
end
local function round(n: string, verdict: string, hash: string?): string
	local quote = if hash then `\nDesign record: {hash}\n` else ""
	return `# Review {n}: x (design mode)\nInputs: y\n\n### F1 [low] a claim\nWhere: a\nEvidence: b\n\nVerdict: {verdict}\n{quote}`
end

local function refusedWith(id: string, ...: string)
	local before = tip()
	local r = tr({ "status", id, "prepared" })
	t.expect(r.ok).toBe(false)
	for _, needle in { ... } do
		if not has(r.stderr, needle) then
			error(`status {id} prepared: stderr lacks {needle}: {r.stderr}`, 2)
		end
	end
	t.expect(tip()).toBe(before)
end
local function statusLine(dir: string, id: string): string
	return string.match(fs.readFile(`{dir}/{id}.md`), "\nstatus: (%S+)\n") or ""
end

return t.spec(
	"c0161 a raft's carried move asks for the approving round of each preparing issue it takes",
	function(it)
		it("sets up a fixture and a prep worktree", function()
			f = trackerfix.new("c0161-review-raft", nil)
			wt = trackerfix.trOk(f, f.main, { "worktree", "prep-raft" })
			trOk({ "sync" })
		end)

		it(
			"a raft's carried move takes a preparing member only after its own approving round with the record",
			function()
				local id = string.match(
					trOk({ "new", "issue", "c", "old-prep-member", "--project", "pickman" }),
					"(%a%d+)"
				) :: string
				local dir = `{wt}/pickman/.tracker/issues/{id}`
				local raft = string.match(
					trOk({ "new", "raft", "chore", "old-prep", id, "--project", "pickman" }),
					"(R%d+)"
				) :: string
				local rdir = `{wt}/pickman/.tracker/rafts/{raft}`
				setLine(`{rdir}/{raft}.md`, "design", "ready")
				setLine(`{dir}/{id}.md`, "design", "ready")
				refusedWith(raft, id, "design-review-001.md")
				-- the old prep kept its reviews in the raft's folder: they do not stand in for the member's own
				write(`{rdir}/design-review-001.md`, round("001", "approve"))
				refusedWith(raft, id, "design-review-001.md")
				write(`{dir}/design-review-001.md`, round("001", "approve"))
				refusedWith(raft, id, "Design record")
				write(`{dir}/design-review-001.md`, round("001", "changes", record(id)))
				refusedWith(raft, id, "Verdict: changes")
				write(`{dir}/design-review-001.md`, round("001", "approve", record(id)))
				trOk({ "status", raft, "prepared" })
				t.expect(string.match(statusLine(dir, id), "^prepared%-") ~= nil).toBe(true)
				t.expect(string.match(statusLine(rdir, raft), "^prepared%-") ~= nil).toBe(true)
			end
		)

		it(
			"work prepared before this rule, with no review, is grouped and prepared into a raft as it was",
			function()
				local stub = "---\nid: c0900\ntype: chore\ntitle: Old\nslug: old\nraft: \ndepends_on: []\nemergent: false\n"
					.. "design: ready\nsize: 10\ncreated: 2026-01-01\nstatus: prepared-quiet-copper-falcon\n---\n\n# c0900\n"
				fixture.git(wt, { "add", "-A" }) -- `new raft` wants a clean tree
				fixture.git(wt, { "commit", "-q", "-m", "tracker: prep the earlier case" })
				trackerfix.elsewhere(f, {
					["pickman/.tracker/issues/c0900/c0900.md"] = stub,
					["pickman/.tracker/issues/c0900/check.sh"] = "true\n",
				}, "an old prepared issue")
				trOk({ "sync" })
				local raft = string.match(
					trOk({ "new", "raft", "chore", "keep-old", "c0900", "--project", "pickman" }),
					"(R%d+)"
				) :: string
				local rpath = `{wt}/pickman/.tracker/rafts/{raft}/{raft}.md`
				setLine(rpath, "design", "ready")
				local text = fs.readFile(rpath)
				text = (string.gsub(text, "## Theme\n<!%-%-.-%-%->", "## Theme\nOne old chore.", 1))
				text = (
					string.gsub(
						text,
						"## Order & dependencies\n<!%-%-.-%-%->",
						"## Order & dependencies\nBy id.",
						1
					)
				)
				write(rpath, text)
				trOk({ "status", raft, "prepared" }) -- no review in c0900's folder or the raft's: nothing is asked of either
				t.expect(string.match(fs.readFile(rpath), "\nstatus: prepared%-") ~= nil).toBe(true)
			end
		)

		it(
			"a member claimed here with status preparing needs its own round, whatever the raft's folder holds",
			function()
				fixture.git(wt, { "add", "-A" })
				fixture.git(wt, { "commit", "-q", "-m", "tracker: prep the old-prep raft" })
				local a = string.match(
					trOk({ "new", "issue", "c", "stamped-b", "--project", "pickman" }),
					"(%a%d+)"
				) :: string
				local raft = string.match(
					trOk({ "new", "raft", "chore", "old-prep-two", a, "--project", "pickman" }),
					"(R%d+)"
				) :: string
				local b = string.match(
					trOk({ "new", "issue", "c", "claimed-here", "--project", "pickman" }),
					"(%a%d+)"
				) :: string
				trOk({ "status", b, "preparing" })
				local rdir = `{wt}/pickman/.tracker/rafts/{raft}`
				setLine(`{rdir}/{raft}.md`, "design", "ready")
				setLine(`{rdir}/{raft}.md`, "issues", `[{a}, {b}]`)
				setLine(`{wt}/pickman/.tracker/issues/{b}/{b}.md`, "raft", raft)
				for _, id in { a, b } do
					setLine(`{wt}/pickman/.tracker/issues/{id}/{id}.md`, "design", "ready")
				end
				write(`{rdir}/design-review-001.md`, round("001", "approve", "aaaaaaaaaaaa"))
				write(
					`{wt}/pickman/.tracker/issues/{a}/design-review-001.md`,
					round("001", "approve", record(a))
				)
				refusedWith(raft, b, "design-review-001.md")
				write(
					`{wt}/pickman/.tracker/issues/{b}/design-review-001.md`,
					round("001", "approve", record(b))
				)
				trOk({ "status", raft, "prepared" })
			end
		)
	end
)
