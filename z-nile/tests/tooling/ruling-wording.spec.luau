--!strict
-- f0421, the owner's ruling of 2026-11-24 ("There should be no strict rule against a model reviewing work of the same model,
-- just that it is not prefered"): no skill, README, AGENTS.md or .models.toml says a reviewer must run on another model than
-- the writer's. The clean-context rule stays, and agy is among the supported CLIs wherever the table is described.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local STRICT = {
	"never runs on the model",
	"never run on the model",
	"never run by the model",
	"never runs on the writer's model",
	"must still resolve to different models",
	"must be another model",
	"other than the one that built",
	"would drop that model",
	"refuses a pair on one model",
	"is refused on the writer's recorded model",
	"cannot run the role, and its step ends",
}

local function files(): { string }
	local out = { `{TOP}/AGENTS.md`, `{TOP}/.models.toml`, `{TOP}/z-nile/README.md` }
	for _, name in fs.readDir(`{TOP}/z-nile/skills`) do
		local path = `{TOP}/z-nile/skills/{name}/SKILL.md`
		if fs.isFile(path) then
			table.insert(out, path)
		end
	end
	return out
end

return t.spec("f0421: a model may review its own text, and the texts say so", function(it)
	it("no skill, README, AGENTS.md or .models.toml says the reviewer must be another model", function()
		for _, path in files() do
			local text = fs.readFile(path)
			for _, phrase in STRICT do
				if string.find(text, phrase, 1, true) ~= nil then
					error(`{path} still says "{phrase}"`, 0)
				end
			end
		end
	end)

	it("zz-review keeps the clean-context rule, and says the same model is allowed and recorded", function()
		local text = fs.readFile(`{TOP}/z-nile/skills/zz-review/SKILL.md`)
		t.expect(string.find(text, "clean context", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "same-model=yes", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "preferred", 1, true) ~= nil).toBe(true)
	end)

	it("zz-rules describes the review sub-table and lists agy among the supported CLIs", function()
		local text = fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
		t.expect(string.find(text, "[clis.<cli>.review]", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "claude, grok, agent, kimi and agy", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "ZN_MODEL", 1, true) ~= nil).toBe(true)
	end)
end)
