--!strict
-- c0283 AC4: the texts that restate the rules agree with the engine: zz-rules (the approve row), z-design step 5, the README and AGENTS.md.
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
	it("zz-rules documents the agent-session refusal and the row", function()
		t.expect(lacks("z-nile/skills/zz-rules/SKILL.md", {
			"**never in an agent session**",
			"a terminal does not help when `CLAUDECODE`, `AI_AGENT`, `CURSOR_AGENT` or `GROK_SESSION_ID` is set",
			"appends `approved | human:<git name> | design=<first 12 hex of that hash>` to the issue's `provenance.md`",
			"in the same `tracker: approve` commit",
			"It records no words.",
			"run `./zn sync` in the prep worktree: it unites the records",
		})).toEqual({})
	end)

	it("z-design, the README and AGENTS.md say a human approves and an agent never does", function()
		t.expect(lacks("z-nile/skills/z-design/SKILL.md", {
			"in a terminal of their own in this worktree (it is refused in any agent session, a `!` command included)",
		})).toEqual({})
		t.expect(lacks("z-nile/README.md", { "**Design approval** (c0283)", "refused in any agent session" }))
			.toEqual({})
		t.expect(lacks("AGENTS.md", { "**Design approval:**", "never try to" })).toEqual({})
	end)
end)
