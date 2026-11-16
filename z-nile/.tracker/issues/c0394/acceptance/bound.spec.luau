--!strict
-- c0394 AC10: `new issue --with <id>` makes a bound issue (an added issue made by the prep that found it, `with:` and
-- `waits: approval` in its frontmatter), and it rafts, folds and unfolds with its issue and is not asked for an approval
-- by ready. Driven through ./zn in two fixtures under .cache/c0394-bound-plan and .cache/c0394-bound-raft
-- (tests/lib/trackerfix), as tests/acceptance/c0116/plan-cli.spec.luau does.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local PREPARING = "preparing-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local KINDS = { f = "feature", d = "defect", c = "chore" }
local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

-- `front` is extra frontmatter lines (size:, with:, waits:); `design` is ready unless the issue is a draft
local function issue(id: string, raft: string, front: string, status: string?, design: string?): string
	return `---\nid: {id}\ntype: {KINDS[string.sub(id, 1, 1)]}\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: {design or "ready"}\ncreated: 2026-11-16\n{front}status: {status or PREPARED}\n---\n\n# {id}\n\n{CAPTURED}\n## Design\n\n### Touched modules\n\n### Affected specs\n\n## Unknowns & experiments\n`
end

local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {string.lower(id)}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-16\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nSeeded.\n\n## Order & dependencies\nBy id.\n`
end

local function seedIssue(seed: { [string]: string }, id: string, text: string)
	seed[`pickman/.tracker/issues/{id}/{id}.md`] = text
	seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
end

local BASE: { [string]: string } = {
	[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
	["pickman/.tracker/architecture.md"] = "# Architecture\n",
	["z-nile/next"] = "issue 300 quiet-copper-falcon\nraft 300 quiet-copper-falcon\n",
}

local function seedFrom(extra: { [string]: string }): { [string]: string }
	local seed = table.clone(BASE)
	for path, text in extra do
		seed[path] = text
	end
	return seed
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function raftOf(dir: string, id: string): string?
	return string.match(fs.readFile(`{dir}/pickman/.tracker/issues/{id}/{id}.md`), "\nraft: (%S*)\n")
end

local plan: trackerfix.Fixture
local raft: trackerfix.Fixture
local W = ""

local function onOrigin(f: trackerfix.Fixture, path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end

return t.spec("c0394 a bound issue travels with its issue", function(it)
	it("new issue --with needs a preparing issue and writes with and waits", function()
		local seed = seedFrom({})
		seedIssue(seed, "c0110", issue("c0110", "", "", PREPARING, "draft")) -- being prepared: the prep that finds
		seedIssue(seed, "c0120", issue("c0120", "", "size: 100\n")) -- prepared: no prep is running on it
		-- R0010 and R0020 are the rafts of the later cases; their members are seeded here
		seedIssue(seed, "c0070", issue("c0070", "R0010", "size: 100\n"))
		seedIssue(seed, "f0080", issue("f0080", "R0010", "size: 100\nwith: c0070\nwaits: approval\n"))
		seedIssue(seed, "c0090", issue("c0090", "R0020", "size: 100\n"))
		seedIssue(seed, "f0100", issue("f0100", "R0020", "size: 100\nwith: c0090\nwaits: approval\n"))
		seed["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "c0070, f0080")
		seed["pickman/.tracker/rafts/R0010/check.sh"] = CHECK
		seed["pickman/.tracker/rafts/R0020/R0020.md"] = raftDoc("R0020", "c0090, f0100")
		seed["pickman/.tracker/rafts/R0020/check.sh"] = CHECK
		raft = trackerfix.new("c0394-bound-raft", seed)
		-- f0100 waits for the user: its approval is not part of the seed
		trackerfix.trOk(raft, raft.main, { "sync" })
		fixture.git(raft.main, { "rm", "-q", "pickman/.tracker/issues/f0100/approval.md" })
		fixture.git(raft.main, { "commit", "-q", "-m", "f0100 waits for approval" })
		fixture.git(raft.main, { "push", "-q", "origin", "HEAD:main" })

		W = trackerfix.trOk(raft, raft.main, { "worktree", "bound-w" })
		local r = trackerfix.tr(
			raft,
			W,
			{ "new", "issue", "c", "found-by-prep", "--with", "c0110", "--project", "pickman" }
		)
		t.expect(r.ok).toBe(true)
		local id = string.match(r.stdout, "(c%d%d%d%d)/c%d%d%d%d%.md") or ""
		t.expect(id ~= "").toBe(true)
		local doc = onOrigin(raft, `pickman/.tracker/issues/{id}/{id}.md`)
		t.expect(doc ~= nil).toBe(true) -- the stub is published
		t.expect(has(doc :: string, "\nwith: c0110\n")).toBe(true)
		t.expect(has(doc :: string, "\nwaits: approval\n")).toBe(true)

		-- an issue that is prepared, one that does not exist, and --with without an issue are refused; nothing is made
		local tip = fixture.git(raft.origin, { "rev-parse", "main" })
		local prepared = trackerfix.tr(
			raft,
			W,
			{ "new", "issue", "c", "found-late", "--with", "c0120", "--project", "pickman" }
		)
		t.expect(prepared.ok).toBe(false)
		t.expect(has(prepared.stderr, "--with c0120: an added issue is made by the prep that found it"))
			.toBe(true)
		local missing = trackerfix.tr(
			raft,
			W,
			{ "new", "issue", "c", "found-none", "--with", "c9999", "--project", "pickman" }
		)
		t.expect(missing.ok).toBe(false)
		t.expect(has(missing.stderr, "--with c9999")).toBe(true)
		t.expect(fixture.git(raft.origin, { "rev-parse", "main" })).toBe(tip)
	end)

	it("raft-plan puts a bound issue in its issue's raft whatever its type", function()
		local seed = seedFrom({})
		seedIssue(seed, "c0010", issue("c0010", "", "size: 100\n"))
		-- a feature and a defect bound to a chore: other types, one of them far over the size cap
		seedIssue(seed, "f0020", issue("f0020", "", "size: 50\nwith: c0010\nwaits: approval\n"))
		seedIssue(seed, "d0030", issue("d0030", "", "size: 5000\nwith: c0010\nwaits: approval\n"))
		-- a bound issue that is not prepared: neither it nor its issue is planned
		seedIssue(seed, "c0040", issue("c0040", "", "size: 100\n"))
		seedIssue(
			seed,
			"f0050",
			issue("f0050", "", "size: 100\nwith: c0040\nwaits: approval\n", PREPARING, "draft")
		)
		plan = trackerfix.new("c0394-bound-plan", seed)
		local out = trackerfix.trOk(plan, plan.main, { "raft-plan" })
		local planned: { string } = {}
		local together = 0
		for line in string.gmatch(out, "[^\n]+") do
			if has(line, "c0010") then
				table.insert(planned, line)
				t.expect(string.sub(line, 1, 2)).toBe("./") -- a command, not a skip
				t.expect(has(line, "f0020")).toBe(true)
				t.expect(has(line, "d0030")).toBe(true)
				together += 1
			elseif has(line, "f0020") or has(line, "d0030") then
				error(`a bound issue is planned apart from its issue: {line}`)
			end
			if has(line, "c0040") or has(line, "f0050") then
				t.expect(string.sub(line, 1, 5)).toBe("skip ")
			end
		end
		t.expect(together).toBe(1)
		t.expect(#planned).toBe(1)
		for line in string.gmatch(out, "[^\n]+") do
			if string.sub(line, 1, 2) == "./" then
				t.expect(has(line, "c0040") or has(line, "f0050")).toBe(false)
			end
		end
	end)

	it("unfold moves an issue and its bound issue together", function()
		-- a worktree made now sees the stub the first case published
		local U = trackerfix.trOk(raft, raft.main, { "worktree", "unfold-w" })
		t.expect(raftOf(U, "c0070")).toBe("R0010")
		t.expect(raftOf(U, "f0080")).toBe("R0010")
		local r = trackerfix.tr(raft, U, { "unfold", "R0010", "c0070" })
		t.expect(r.ok).toBe(true)
		-- the bound issue leaves with its issue: no raft on either, and the raft no longer lists it
		t.expect(raftOf(U, "c0070")).toBe("")
		t.expect(raftOf(U, "f0080")).toBe("")
		local text = fs.readFile(`{U}/pickman/.tracker/rafts/R0010/R0010.md`)
		local listed = string.match(text, "\nissues: %[([^\n]*)%]") or ""
		t.expect(has(listed, "f0080")).toBe(false)
		t.expect(has(listed, "c0070")).toBe(false)
	end)

	it("ready asks no approval of a waiting member", function()
		trackerfix.trOk(raft, raft.main, { "sync" })
		-- c0090 is approved (the seed); f0100 waits for the user and has no approval
		t.expect(fs.isFile(`{raft.main}/pickman/.tracker/issues/c0090/approval.md`)).toBe(true)
		t.expect(fs.isFile(`{raft.main}/pickman/.tracker/issues/f0100/approval.md`)).toBe(false)
		local r = trackerfix.tr(raft, raft.main, { "ready", "R0020" })
		if not r.ok then
			error(`ready R0020 refused: {r.stderr}{r.stdout}`, 0)
		end
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "readied R0020")).toBe(true)
		t.expect(onOrigin(raft, "pickman/.tracker/issues/active/c0090/c0090.md") ~= nil).toBe(true)
		t.expect(onOrigin(raft, "pickman/.tracker/issues/active/f0100/f0100.md") ~= nil).toBe(true)
	end)
end)
