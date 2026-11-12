--!strict
-- c0283 AC4: the texts that restate the rules agree with the engine: zz-rules (the approve row, Landing step 3 and the
-- dispatcher paragraph), z-design (steps 5 and 6), the README, AGENTS.md and the root .models.toml.
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
-- the needles of `needles` that `path` still holds
local function holds(path: string, needles: { string }): { string }
	local text = fs.readFile(`{top}/{path}`)
	local out: { string } = {}
	for _, needle in needles do
		if string.find(text, needle, 1, true) then
			table.insert(out, needle)
		end
	end
	return out
end

return t.spec("c0283 the texts", function(it)
	it("zz-rules documents the agent-session refusal, the row and the prep gate", function()
		t.expect(lacks("z-nile/skills/zz-rules/SKILL.md", {
			"**never in an agent session**",
			"a terminal does not help when `CLAUDECODE`, `AI_AGENT`, `CURSOR_AGENT` or `GROK_SESSION_ID` is set",
			"appends `approved | human:<git name> | contract=<first 12 hex of that hash>` to the issue's `provenance.md`",
			"in the same `tracker: approve` commit",
			"It records no words.",
			"only a `raft` gate (a `prep` gate never merges)",
			"the prep PR #<n> waits for the user's approval and merge",
			"`auto_merge` keeps accepting `prep` as a name, with no effect",
			"a prep PR waits for the user, who approves the design (`./zn approve`) and merges it",
		})).toEqual({})
		t.expect(holds("z-nile/skills/zz-rules/SKILL.md", {
			"passes the prep and rafting gates itself",
			"passes a `prep` or `raft` gate itself",
		})).toEqual({})
	end)

	it("z-design, the README and AGENTS.md say a human approves and an agent never does", function()
		t.expect(lacks("z-nile/skills/z-design/SKILL.md", {
			"in a terminal of their own in this worktree (it is refused in any agent session, a `!` command included)",
			"the dispatcher stops at the prep gate for the user, who approves the design",
		})).toEqual({})
		t.expect(
			holds(
				"z-nile/skills/z-design/SKILL.md",
				{ "the dispatcher passes the gate (the user started it)" }
			)
		)
			.toEqual({})
		t.expect(lacks("z-nile/README.md", { "**Design approval** (c0283)", "refused in any agent session" }))
			.toEqual({})
		t.expect(lacks("AGENTS.md", { "**Design approval:**", "never try to" })).toEqual({})
	end)

	it("the root .models.toml no longer lists prep as a merge gate", function()
		local models = fs.readFile(`{top}/.models.toml`)
		t.expect(string.find(models, 'auto_merge = ["raft"]', 1, true) ~= nil).toBe(true)
		t.expect((string.find(models, 'auto_merge = ["prep"', 1, true))).toBe(nil)
	end)
end)
