--!strict
-- c0410 AC5: `tracker.sh metrics` reports review rounds per raft, counted from the files, so the
-- effect of second-order reviews can be measured. Done rafts never change, so their counts are fixed.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local process = require("@lune/process")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

-- c0120 override: specs run from their project's home; the real tree and its tooling are at the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function metrics(cwd: string?): string
	local r = process.exec("scripts/tracker.sh", { "metrics" }, { cwd = cwd or TOP }) -- c0120 override: the real tree at the top
	if not r.ok then
		error(r.stderr)
	end
	return r.stdout
end

-- rows of the review-rounds table: { raft, design, code }
local function rows(out: string): { { string } }
	local s = string.find(out, "| raft | design rounds | code rounds | format |", 1, true)
	assert(s, "no review rounds table")
	local out2: { { string } } = {}
	for line in string.gmatch(string.sub(out, s :: number), "[^\n]+") do
		local id, d, c, f = string.match(line, "^| (R%d%d%d%d) | (%d+) | (%d+) | ([%w%-]+) |$")
		if id then
			table.insert(out2, { id :: string, d :: string, c :: string, f :: string })
		end
	end
	return out2
end

-- A throwaway repo copy with its own small tracker tree, so the cases the real tracker lacks (a raft
-- with no reviews, reviews inside an issue directory) are covered without touching tracker/.
local SB = ".cache/c0410-sandbox"
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]*$") :: string)
	fs.writeFile(path, text)
end
local function sandbox(): string
	if fs.isDir(SB) then
		fs.removeDir(SB)
	end
	fs.writeDir(SB)
	engine.copy(".", SB) -- c0114 override: ./zn, scripts/ and z-nile/ (c0120: pickman's root is pickman/.tracker)
	-- c0120 override: the root files are at the checkout's top, not in the home the spec runs from
	fs.copy(`{TOP}/.luaurc`, `{SB}/.luaurc`)
	fs.copy(`{TOP}/rokit.toml`, `{SB}/rokit.toml`)
	local front = "---\nid: %s\ntype: chore\ntitle: T\nslug: t\n---\n\n# %s\n"
	local classic = "# Review 001\n\n### F1 [low] x\nWhere: a\nEvidence: b\nFix: c\n\nVerdict: approve\n"
	local second =
		"# Review 001\n\n### F1 [low] x\nWhere: a\nEvidence: b\nCritique: c\nConsequences: none\nRecommendation: d\n\nVerdict: approve\n"
	-- c0120 override: pickman's items live in pickman/.tracker (engine.REGISTRY's layout)
	write(`{SB}/pickman/.tracker/rafts/R0010/R0010.md`, string.format(front, "R0010", "R0010"))
	write(`{SB}/pickman/.tracker/rafts/R0010/design-review-001.md`, classic)
	write(`{SB}/pickman/.tracker/rafts/R0020/R0020.md`, string.format(front, "R0020", "R0020")) -- no reviews yet
	write(`{SB}/pickman/.tracker/rafts/R0030/R0030.md`, string.format(front, "R0030", "R0030"))
	write(`{SB}/pickman/.tracker/rafts/R0030/design-review-001.md`, second)
	write(`{SB}/pickman/.tracker/rafts/R0030/design-review-002.md`, second)
	write(`{SB}/pickman/.tracker/rafts/R0030/design-refute-001.md`, "- F1: fixed: x; consequences: none\n")
	write(`{SB}/pickman/.tracker/rafts/R0030/review-001.md`, second)
	-- reviews inside an issue directory are not counted for any raft
	write(
		`{SB}/pickman/.tracker/issues/c0010/c0010.md`,
		"---\nid: c0010\ntype: chore\ntitle: X\nslug: x\nraft: R0030\n---\n\n# c0010\n"
	)
	write(`{SB}/pickman/.tracker/issues/c0010/design-review-001.md`, second)
	write(`{SB}/pickman/.tracker/issues/c0010/review-001.md`, second)
	return SB
end

return t.spec("c0410 review rounds in metrics", function(it)
	it("in a sandbox tracker: none for a raft without reviews, issue directories not counted", function()
		local ok, err = pcall(function()
			local got = rows(metrics(sandbox()))
			t.expect(got).toEqual({
				{ "R0010", "1", "0", "classic" },
				{ "R0020", "0", "0", "none" },
				{ "R0030", "2", "1", "second-order" },
			})
		end)
		if fs.isDir(SB) then
			fs.removeDir(SB)
		end
		if not ok then
			error(err, 0)
		end
	end)

	local out = metrics()
	local got = rows(out)

	it("counts design-review and review files per raft", function()
		local by: { [string]: { string } } = {}
		for _, r in got do
			by[r[1]] = r
		end
		-- real rafts, by the ids they have now (c0870: the user's compaction renumbers them)
		local r10, r30, r50, r70 =
			renamed.id("R0010"), renamed.id("R0030"), renamed.id("R0050"), renamed.id("R0070")
		t.expect(by[r10]).toEqual({ r10, "3", "2", "classic" })
		t.expect(by[r30]).toEqual({ r30, "3", "2", "classic" })
		t.expect(by[r50]).toEqual({ r50, "4", "1", "classic" })
		t.expect(by[r70][4]).toBe("second-order") -- its first design review used the new format
	end)

	it("prints after the per-type table and before the rework lines", function()
		local types = string.find(out, "| type | issues |", 1, true)
		local rounds = string.find(out, "| raft | design rounds |", 1, true)
		local rework = string.find(out, "Rework = ", 1, true)
		t.expect(types ~= nil and rounds ~= nil and rework ~= nil).toBe(true)
		t.expect((types :: number) < (rounds :: number) and (rounds :: number) < (rework :: number))
			.toBe(true)
	end)

	it("lists every raft once, sorted by id", function()
		local ids = {}
		for _, r in got do
			table.insert(ids, r[1])
		end
		local want = {}
		-- c0114 override: rafts live under every project root (c0120: pickman's root is pickman/.tracker)
		for _, base in
			{
				"pickman/.tracker/rafts",
				"pickman/.tracker/rafts/active",
				"pickman/.tracker/rafts/done",
				"z-nile/.tracker/rafts",
				"z-nile/.tracker/rafts/active",
				"z-nile/.tracker/rafts/done",
			}
		do
			for _, name in fs.readDir(`{TOP}/{base}`) do -- c0120 override: the roots are at the checkout's top
				if string.match(name, "^R%d%d%d%d$") then
					table.insert(want, name)
				end
			end
		end
		table.sort(want)
		t.expect(ids).toEqual(want)
	end)
end)
