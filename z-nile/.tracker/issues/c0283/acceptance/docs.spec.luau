--!strict
-- c0283 AC7: the texts that restate the approval rules agree with the engine: zz-rules (Design approval and the
-- dispatcher paragraph), z-design step 5, the README, AGENTS.md, the root .models.toml and ./zn's usage.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- the needles of `needles` that `path` lacks
local function lacks(path: string, needles: { string }): { string }
	local text = fs.readFile(`{top}/{path}`)
	local out: { string } = {}
	for _, needle in needles do
		if not string.find(text, needle, 1, true) then
			table.insert(out, needle)
		end
	end
	return out
end

return t.spec("c0283 the texts", function(it)
	it("zz-rules documents the approval, the doors, the frozen list and the prep gate", function()
		t.expect(lacks("z-nile/skills/zz-rules/SKILL.md", {
			"## Design approval",
			"`./zn approve <id>`",
			"design=<hash>",
			"**It is refused in any agent session**",
			"in a terminal of their own",
			"has no current approval",
			"was redesigned since its approval",
			"refuses under `ZN_DISPATCH`",
			"`fold`, `new raft` and `ready` refuse",
			"`unapproved-prepared`",
			"`z-nile/provenance-exempt.txt`",
			"`./zn provenance freeze`",
			"with no list on `origin/main` the doors enforce nothing",
			"a `prep` gate never merges",
			"the prep PR #<n> waits for the user's approval and merge",
			"`auto_merge` keeps accepting `prep` as a name, with no effect",
			'`--said "<their words>"`',
			"has changes that are not committed",
			"`exempt-list-gone`",
			"`./zn provenance freeze --check`",
			"Before merging a prep PR, merge `origin/main`, rerun `./zn status <id> prepared`",
		})).toEqual({})
		-- the sentences that said the dispatcher passes the prep gate are gone
		local zz = fs.readFile(`{top}/z-nile/skills/zz-rules/SKILL.md`)
		t.expect((string.find(zz, "passes the prep and rafting gates itself", 1, true))).toBe(nil)
		t.expect((string.find(zz, "passes a `prep` or `raft` gate itself", 1, true))).toBe(nil)
		local zd = fs.readFile(`{top}/z-nile/skills/z-design/SKILL.md`)
		t.expect((string.find(zd, "the dispatcher passes the gate (the user started it)", 1, true))).toBe(nil)
	end)

	it("z-design step 5 says who approves and in what order", function()
		t.expect(lacks("z-nile/skills/z-design/SKILL.md", {
			"**The design is approved by a human, never by you or the reviewer**",
			"`./zn approve <id>` in a terminal of their own",
			"**then run `./zn status <id> prepared`**",
			"needs a fresh `./zn approve`",
			"it never runs `approve` or `status prepared`",
		})).toEqual({})
	end)

	it("the README, AGENTS.md, .models.toml and the usage restate it", function()
		t.expect(lacks("z-nile/README.md", { "**Design approval** (c0283)", "refused in any agent session" }))
			.toEqual({})
		t.expect(lacks("AGENTS.md", { "**Design approval:**", "never try to" })).toEqual({})
		local models = fs.readFile(`{top}/.models.toml`)
		t.expect(string.find(models, 'auto_merge = ["raft"]', 1, true) ~= nil).toBe(true)
		t.expect(
			string.find(models, '"prep"', 1, true) ~= nil
				and string.find(models, 'auto_merge = ["prep"', 1, true) ~= nil
		).toBe(false)
		t.expect(lacks("z-nile/engine/main.luau", { "  approve <id>  ", "  provenance freeze [--check]  " }))
			.toEqual({})
	end)
end)
