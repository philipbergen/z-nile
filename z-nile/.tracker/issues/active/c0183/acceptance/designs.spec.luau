--!strict
-- c0183 AC3: the approved designs moved from c0183's document into the new roots, and the four stub maps. Each file's
-- expected text is pinned by its SHA-256, computed in prep from c0183's blocks by experiments/E4-digests.py (design
-- review 001 F2: never read from the issue document, which the executor could edit and a compaction renames). This
-- spec is promoted and runs in every later gate, so a file passes when some version of it (the working file, or the
-- file at any commit that touched it) has the pinned digest: later product decisions and growing maps never fail it,
-- and a wrong first commit fixed later on the branch still passes. The exact claim about the delivered tree (today's
-- files have these digests) is check.sh's AC3, which runs at done and never again (design review 001 F1).
-- These specs run from z-nile/: the checkout is read from its top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- the moved designs, then the stub maps: path, SHA-256 of the exact text
local PINNED: { { string } } = {
	{ "snake/.tracker/game-design.md", "6b8d831adc1fac1772b34037efbafdceb519e727394719645c8a1de4b111307c" },
	{
		"invaders/.tracker/game-design.md",
		"512c8d085d2dbf35702e43d5e1b78289e2efae4c91f373f9f09e6b525f82a71d",
	},
	{
		"asteroids/.tracker/game-design.md",
		"12e8c3351f9427a23fed5b98cef338c68a2bce6ee3a75e815200018995aac3b5",
	},
	{ "portal/.tracker/game-design.md", "5007ca3d719277ebfc75b4e62db9738a1701f08be8836831f4fc9f63ffe4e718" },
	{ "arcade/.tracker/architecture.md", "01cc48774876255c5a46fcc8f5e59dbf5b5f4ccd04a250849bdeb432e6bd1f10" },
	{ "portal/.tracker/architecture.md", "3d5b251bfed0b8796c4e6c5701b34e7f0f4129f25900f9c0de5b9d5812623db6" },
	{ "snake/.tracker/architecture.md", "4450e243e036f6687ff7d0b260949f00b2a61d6938a3a1186fcd3e7d2ffb69ca" },
	{
		"invaders/.tracker/architecture.md",
		"7486a2368eafdf281bda75e26afec789c5e7c0a2c0ca52f697ef31c3173b3407",
	},
	{
		"asteroids/.tracker/architecture.md",
		"7c325cfebe4a1f54b21dc7b38f8bef1b926afb09cca9f1c0b083ed434f05ddb5",
	},
}

-- every version of `rel` there has been: the working file, then the file at each commit that touched it (newest
-- first); empty when it never existed
local function versions(rel: string): { string }
	local out: { string } = {}
	local path = `{TOP}/{rel}`
	if fs.isFile(path) then
		table.insert(out, fs.readFile(path))
	end
	local log = process.exec("git", { "log", "--format=%H", "--", rel }, { cwd = TOP })
	if not log.ok then
		error(`git log -- {rel} failed: {log.stderr}`)
	end
	for sha in string.gmatch(log.stdout, "%x+") do
		local r = process.exec("git", { "show", `{sha}:{rel}` }, { cwd = TOP })
		if r.ok then -- a commit that deleted it has no version
			table.insert(out, r.stdout)
		end
	end
	return out
end

return t.spec("c0183 the designs move into the new roots", function(it)
	it("AC3: some version of each moved design and stub map has its pinned digest", function()
		local missing: { string } = {}
		for _, row in PINNED do
			local found = false
			for _, text in versions(row[1]) do
				if serde.hash("sha256", text) == row[2] then
					found = true
					break
				end
			end
			if not found then
				table.insert(missing, row[1])
			end
		end
		t.expect(missing).toEqual({})
	end)
end)
