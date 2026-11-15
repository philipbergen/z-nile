--!strict
-- c0293 AC4: SETUP.md says how each agent finds a project's own AGENTS.md: Claude Code through the folder's
-- CLAUDE.md import, the other agents by reading it.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function setup(): string
	return fs.readFile(`{root}/SETUP.md`)
end

local function says(line: string)
	if string.find(setup(), line, 1, true) == nil then
		error(`SETUP.md does not say: {line}`)
	end
end

local function unsays(line: string)
	if string.find(setup(), line, 1, true) ~= nil then
		error(`SETUP.md still says: {line}`)
	end
end

return t.spec("c0293 SETUP.md", function(it)
	it("AC4: Claude Code loads a project's AGENTS.md through that folder's CLAUDE.md", function()
		says(
			"- **Claude Code**: `CLAUDE.md` imports `AGENTS.md`, and each project folder's `CLAUDE.md` imports that folder's `AGENTS.md`, which Claude Code loads once it works on a file there."
		)
		unsays("- **Claude Code**: `CLAUDE.md` imports `AGENTS.md`. The hooks")
	end)

	it("AC4: the other agents read the root's AGENTS.md and their project folder's", function()
		says(
			"- **Other agents** (Grok, Codex, …): read `AGENTS.md`, and the `AGENTS.md` of the project folder they work in."
		)
		unsays("- **Other agents** (Grok, Codex, …): read `AGENTS.md`. For execution")
	end)
end)
