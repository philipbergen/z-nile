--!strict
-- d0295 AC3: the commands before `./zn start` refuse an Order start would refuse. The carried
-- `status <R> prepared` refuses a raft whose Order names a non-member or a member twice, or whose members'
-- depends_on form a cycle, publishes nothing and leaves the raft preparing; the same order under
-- `## Cross-raft waits` is prepared. `./zn work next` does not offer such a prepared raft and says why. `./zn ready` refuses such a prepared
-- raft and publishes nothing, readies one whose cross-raft order is under `## Cross-raft waits`, and its prompt carries
-- that section. Fixture under .cache/d0295-order (tests/lib/trackerfix), driven the way z-raft and z-ready run it.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local P = "pickman/.tracker"

local function issue(id: string, raft: string, deps: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: [{deps or ""}]\nemergent: false\n`
		.. `design: ready\ncreated: 2026-11-15\nsize: 100\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local function raftDoc(id: string, member: string, order: string, waits: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {string.lower(id)}\nsingle: true\nissues: [{member}]\n`
		.. `design: ready\ncreated: 2026-11-15\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nOne chore.\n\n`
		.. `## Order & dependencies\n{order}\n\n`
		.. (if waits then `## Cross-raft waits\n{waits}\n\n` else "")
		.. "## Risks & rollback\n"
end

local f: trackerfix.Fixture
local A, B, R, R2 = "", "", "", ""

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function tr(cwd: string, args: { string }): fixture.Result
	return trackerfix.tr(f, cwd, args)
end
local function refused(cwd: string, args: { string }, ...: string)
	local before = tip()
	local r = tr(cwd, args)
	if r.ok then
		error(`{table.concat(args, " ")} was accepted: {r.stdout}`, 2)
	end
	for _, needle in { ... } do
		if not has(r.stderr, needle) then
			error(`{table.concat(args, " ")}: stderr lacks {needle}: {r.stderr}`, 2)
		end
	end
	t.expect(tip()).toBe(before)
end
-- the raft document with everything from its Order heading to the next section after it replaced
local function writeOrder(doc: string, order: string, waits: string?)
	local text = fs.readFile(doc)
	text = (string.gsub(text, "## Theme\n[^\n]*", "## Theme\nTwo chores on one surface.", 1))
	local s = string.find(text, "\n## Order & dependencies\n", 1, true)
	local e = string.find(text, "\n## Experiments phase\n", 1, true)
		or string.find(text, "\n## Risks & rollback\n", 1, true)
	assert(s and e, `{doc} has no Order section and a section after it`)
	local body = `\n## Order & dependencies\n{order}\n`
		.. (if waits then `\n## Cross-raft waits\n{waits}\n` else "")
	fs.writeFile(doc, string.sub(text, 1, s - 1) .. body .. string.sub(text, e))
end
local function setLine(path: string, key: string, value: string)
	local text = fs.readFile(path)
	local s, e = string.find(text, `\n{key}:[^\n]*\n`)
	assert(s and e, `{path} has no {key}:`)
	fs.writeFile(path, string.sub(text, 1, s) .. `{key}: {value}\n` .. string.sub(text, e + 1))
end
local function statusOf(path: string): string
	return string.match(fs.readFile(path), "\nstatus: (%S+)\n") or ""
end

return t.spec("d0295 an Order start would refuse is refused before it", function(it)
	it("sets up two raftless prepared chores, two prepared rafts and a rafting worktree", function()
		f = trackerfix.new("d0295-order", {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
			[`{P}/architecture.md`] = "# map\n",
			[`{P}/issues/c0010/c0010.md`] = issue("c0010", ""),
			[`{P}/issues/c0010/check.sh`] = CHECK,
			[`{P}/issues/c0020/c0020.md`] = issue("c0020", ""),
			[`{P}/issues/c0020/check.sh`] = CHECK,
			-- two prepared chores that depend on each other: start refuses their raft whatever its Order says
			[`{P}/issues/c0050/c0050.md`] = issue("c0050", "", "c0060"),
			[`{P}/issues/c0050/check.sh`] = CHECK,
			[`{P}/issues/c0060/c0060.md`] = issue("c0060", "", "c0050"),
			[`{P}/issues/c0060/check.sh`] = CHECK,
			-- R0090's shape: its Order names another raft's issue to say who merges first
			[`{P}/rafts/R0030/R0030.md`] = raftDoc(
				"R0030",
				"c0030",
				"One member, c0030. It merges before c0099's raft."
			),
			[`{P}/rafts/R0030/check.sh`] = CHECK,
			[`{P}/issues/c0030/c0030.md`] = issue("c0030", "R0030"),
			[`{P}/issues/c0030/check.sh`] = CHECK,
			[`{P}/rafts/R0040/R0040.md`] = raftDoc(
				"R0040",
				"c0040",
				"One member, c0040. R0030 is unrelated.",
				"It merges before c0099's raft (WAIT-MARKER)."
			),
			[`{P}/rafts/R0040/check.sh`] = CHECK,
			[`{P}/issues/c0040/c0040.md`] = issue("c0040", "R0040"),
			[`{P}/issues/c0040/check.sh`] = CHECK,
		})
		A = trackerfix.trOk(f, f.main, { "worktree", "raft-a" })
		R = string.match(
			trackerfix.trOk(
				f,
				A,
				{ "new", "raft", "chore", "pair", "c0010", "c0020", "--project", "pickman" }
			),
			"(R%d+)"
		) :: string
		local dir = `{A}/{P}/rafts/{R}`
		setLine(`{dir}/{R}.md`, "design", "ready")
		local grouped = string.match(fs.readFile(`{dir}/{R}.md`), "\ngrouped: ([^\n]*)\n") or "[]"
		fs.writeFile(`{dir}/design-review-001.md`, `# Review 001\n\nGrouped: {grouped}\n\nVerdict: approve\n`)
		B = trackerfix.trOk(f, f.main, { "worktree", "raft-b" })
		R2 = string.match(
			trackerfix.trOk(
				f,
				B,
				{ "new", "raft", "chore", "loop", "c0050", "c0060", "--project", "pickman" }
			),
			"(R%d+)"
		) :: string
		local dir2 = `{B}/{P}/rafts/{R2}`
		setLine(`{dir2}/{R2}.md`, "design", "ready")
		local grouped2 = string.match(fs.readFile(`{dir2}/{R2}.md`), "\ngrouped: ([^\n]*)\n") or "[]"
		fs.writeFile(
			`{dir2}/design-review-001.md`,
			`# Review 001\n\nGrouped: {grouped2}\n\nVerdict: approve\n`
		)
	end)

	it("status <R> prepared refuses an Order that names an issue that is not a member", function()
		local doc = `{A}/{P}/rafts/{R}/{R}.md`
		writeOrder(doc, "c0010, then c0020. This raft merges before c0099's raft.")
		local before = statusOf(doc)
		refused(
			A,
			{ "status", R, "prepared" },
			`{R}'s Order & dependencies: `,
			`c0099 is in {R}'s Order and is not a member`,
			"## Cross-raft waits"
		)
		t.expect(statusOf(doc)).toBe(before)
		t.expect(string.match(before, "^preparing%-") ~= nil).toBe(true)
	end)

	it("status <R> prepared refuses a member named twice, as a layer branch names it", function()
		local doc = `{A}/{P}/rafts/{R}/{R}.md`
		writeOrder(doc, `c0010 (\`{R}/1/c0010\`), then c0020.`)
		refused(A, { "status", R, "prepared" }, `c0010 is listed twice in {R}'s Order`)
	end)

	it(
		"status <R> prepared takes the same order with the other raft's issue under Cross-raft waits",
		function()
			local doc = `{A}/{P}/rafts/{R}/{R}.md`
			writeOrder(doc, "c0010, then c0020.", "This raft merges before c0099's raft.")
			trackerfix.trOk(f, A, { "status", R, "prepared" })
			t.expect(string.match(statusOf(doc), "^prepared%-") ~= nil).toBe(true)
			local rows = trackerfix.trOk(f, A, { "stack", R }) -- start's reading of the same Order
			t.expect(has(rows, `1 {R}/1/c0010 c0010`)).toBe(true)
			t.expect(has(rows, `2 {R}/2/c0020 c0020`)).toBe(true)
		end
	)

	it(
		"status <R> prepared refuses a raft whose members' depends_on form a cycle, whatever its Order says",
		function()
			local doc = `{B}/{P}/rafts/{R2}/{R2}.md`
			writeOrder(doc, "By id.", "None.")
			local before = statusOf(doc)
			refused(
				B,
				{ "status", R2, "prepared" },
				`{R2}'s Order & dependencies: `,
				"dependency cycle among: c0050, c0060",
				"depends_on must not form a cycle"
			)
			t.expect(statusOf(doc)).toBe(before)
		end
	)

	it("work next does not offer the raft whose Order start would refuse, and says why", function()
		local r = fixture.exec(f.main, "./zn", { "work", "next" })
		local said = r.stdout .. r.stderr
		if not r.ok then
			error(said)
		end
		t.expect(has(said, "R0030: ready")).toBe(false)
		t.expect(has(said, "c0099 is in R0030's Order and is not a member")).toBe(true)
		t.expect(has(said, "R0040: ready")).toBe(true) -- the same order under Cross-raft waits is offered
	end)

	it("ready refuses a prepared raft whose Order names an issue that is not a member", function()
		refused(
			f.main,
			{ "ready", "R0030" },
			"c0099 is in R0030's Order and is not a member",
			"## Cross-raft waits"
		)
		t.expect(fs.isFile(`{f.main}/{P}/rafts/R0030/R0030.md`)).toBe(true) -- still in the backlog
		t.expect(fs.isFile(`{f.main}/{P}/rafts/active/R0030/prompt.md`)).toBe(false)
	end)

	it(
		"ready takes a raft whose cross-raft order is under Cross-raft waits, and the prompt carries it",
		function()
			trackerfix.trOk(f, f.main, { "ready", "R0040" })
			local prompt = fs.readFile(`{f.main}/{P}/rafts/active/R0040/prompt.md`)
			t.expect(has(prompt, "### Order & dependencies\nOne member, c0040. R0030 is unrelated.\n"))
				.toBe(true)
			t.expect(has(prompt, "### Cross-raft waits\nIt merges before c0099's raft (WAIT-MARKER).\n"))
				.toBe(true)
			t.expect(has(prompt, "{{")).toBe(false)
		end
	)
end)
