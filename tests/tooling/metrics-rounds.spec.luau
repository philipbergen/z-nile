--!strict
-- The `format` column of `tracker.sh metrics` comes from a raft's FIRST design review only, and only
-- from a line that starts with `Consequences:`. That is how the before/after comparison of review
-- rounds separates old rafts from new ones, so both edges are pinned here (c0410, review-001 F2).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local SB = ".cache/metrics-rounds-sandbox"

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]*$") :: string)
	fs.writeFile(path, text)
end

local CLASSIC = "# Review 001\n\n### F1 [low] x\nWhere: a\nEvidence: b\nFix: c\n\nVerdict: approve\n"
local SECOND =
	"# Review 002\n\n### F1 [low] x\nWhere: a\nEvidence: b\nCritique: c\nConsequences: none\nRecommendation: d\n\nVerdict: approve\n"
-- the word appears in the middle of a line, not at the start of one
local MIDLINE =
	"# Review 001\n\n### F1 [low] x\nWhere: a\nEvidence: the fix has Consequences: it brings\nFix: c\n\nVerdict: approve\n"

local function build()
	if fs.isDir(SB) then
		fs.removeDir(SB)
	end
	fs.writeDir(SB)
	fs.copy("scripts", `{SB}/scripts`)
	fs.copy(".luaurc", `{SB}/.luaurc`)
	fs.copy("rokit.toml", `{SB}/rokit.toml`)
	local front = "---\nid: %s\ntype: chore\ntitle: T\nslug: t\n---\n\n# %s\n"
	-- RA: a mixed raft. Its first round is classic and its latest is second-order.
	write(`{SB}/tracker/rafts/R0010/R0010.md`, string.format(front, "R0010", "R0010"))
	write(`{SB}/tracker/rafts/R0010/design-review-001.md`, CLASSIC)
	write(`{SB}/tracker/rafts/R0010/design-review-002.md`, SECOND)
	-- RB: `Consequences:` only mid-line
	write(`{SB}/tracker/rafts/R0020/R0020.md`, string.format(front, "R0020", "R0020"))
	write(`{SB}/tracker/rafts/R0020/design-review-001.md`, MIDLINE)
	-- RC: second-order from its first round
	write(`{SB}/tracker/rafts/R0030/R0030.md`, string.format(front, "R0030", "R0030"))
	write(`{SB}/tracker/rafts/R0030/design-review-001.md`, SECOND)
end

-- { raft id, design rounds, code rounds, format } for each row of the review-rounds table
local function rows(): { { string } }
	local r = process.exec("scripts/tracker.sh", { "metrics" }, { cwd = SB })
	if not r.ok then
		error(r.stderr)
	end
	local out: { { string } } = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		local id, d, c, f = string.match(line, "^| (R%d%d%d%d) | (%d+) | (%d+) | ([%w%-]+) |$")
		if id then
			table.insert(out, { id :: string, d :: string, c :: string, f :: string })
		end
	end
	return out
end

return t.spec("metrics review-rounds format", function(it)
	local got: { { string } } = {}
	local ok, err = pcall(function()
		build()
		got = rows()
	end)
	if fs.isDir(SB) then
		fs.removeDir(SB)
	end
	if not ok then
		error(err, 0)
	end

	local by: { [string]: { string } } = {}
	for _, r in got do
		by[r[1]] = r
	end

	it("takes the format from the first design review, not the latest", function()
		t.expect(by.R0010).toEqual({ "R0010", "2", "0", "classic" })
	end)

	it("needs Consequences: at the start of a line", function()
		t.expect(by.R0020).toEqual({ "R0020", "1", "0", "classic" })
	end)

	it("recognises a second-order first round", function()
		t.expect(by.R0030).toEqual({ "R0030", "1", "0", "second-order" })
	end)
end)
