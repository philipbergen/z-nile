--!strict
-- c0293 AC3: each project folder holds its own AGENTS.md (its description, where its decisions are, and its two
-- skills) and a CLAUDE.md that imports it, so Claude Code loads it once it works on a file there. The root keeps
-- none of a project's parts, and a project's file keeps none of the root's.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- every registered project but z-nile (c0184's rule: a promoted check over projects runs over the registry)
local HOMES: { string } = {}
for _, p in projects.load(root).projects do
	if p.name ~= "z-nile" then
		table.insert(HOMES, p.home)
	end
end
-- what each project's AGENTS.md must name beyond its two skill rows (arcade, a library, keeps no game design)
local NAMES: { [string]: { string } } = {
	pickman = {
		"A first-person Pac-Man clone for Roblox, built with Rojo, strict Luau, and Lune for headless tests.",
		"The game is the `pickman` project, in `pickman/`",
		"`pickman/.tracker/game-design.md`",
		"`pickman/.tracker/architecture.md`",
	},
	arcade = { "The library every place shares", "`arcade/.tracker/architecture.md`" },
	portal = {
		"The experience's start place",
		"`portal/.tracker/game-design.md`",
		"`portal/.tracker/architecture.md`",
	},
	snake = {
		"A first-person Snake game",
		"`snake/.tracker/game-design.md`",
		"`snake/.tracker/architecture.md`",
	},
	invaders = {
		"A first-person Space Invaders game",
		"`invaders/.tracker/game-design.md`",
		"`invaders/.tracker/architecture.md`",
	},
	asteroids = {
		"A first-person Asteroids game",
		"`asteroids/.tracker/game-design.md`",
		"`asteroids/.tracker/architecture.md`",
	},
}
-- the root's own paragraphs, which no project's file repeats
local ROOT_ONLY = {
	"**Non-negotiable:**",
	"**Subagents:**",
	"**Processes:**",
	"**No check may ever change the real repository.**",
	"| `z-nile/skills/",
}

local function read(rel: string): string
	local path = `{root}/{rel}`
	if not fs.isFile(path) then
		error(`{rel} does not exist`)
	end
	return fs.readFile(path)
end

local function has(rel: string, text: string, needle: string)
	if string.find(text, needle, 1, true) == nil then
		error(`{rel} does not say: {needle}`)
	end
end

local function lacks(rel: string, text: string, needle: string)
	if string.find(text, needle, 1, true) ~= nil then
		error(`{rel} still says: {needle}`)
	end
end

return t.spec("c0293 project AGENTS.md files", function(it)
	it("AC3: each project folder's CLAUDE.md is exactly the import of its AGENTS.md", function()
		if #HOMES < 6 then
			error(`the registry lists {#HOMES} projects besides z-nile, fewer than the six of c0293's day`)
		end
		for _, h in HOMES do
			local text = read(`{h}/CLAUDE.md`)
			if text ~= "@AGENTS.md\n" then
				error(`{h}/CLAUDE.md is {string.format("%q", text)}, not "@AGENTS.md\\n"`)
			end
		end
	end)

	it(
		"AC3: each project's AGENTS.md names itself, its decisions and its two skills, and none of the root's rules",
		function()
			for _, h in HOMES do
				local rel = `{h}/AGENTS.md`
				local text = read(rel)
				if string.sub(text, 1, #h + 3) ~= `# {h}\n` then
					error(`{rel} does not start with "# {h}"`)
				end
				has(rel, text, `| \`{h}/skills/{h}-arch/SKILL.md\` |`)
				has(rel, text, `| \`{h}/skills/{h}-test/SKILL.md\` |`)
				has(rel, text, `designing or writing anything in \`{h}/src/\``)
				local names: { string } = NAMES[h] or {}
				for _, n in names do
					has(rel, text, n)
				end
				for _, n in ROOT_ONLY do
					lacks(rel, text, n)
				end
			end
		end
	)

	it("AC3: the root AGENTS.md keeps none of a project's parts", function()
		local text = read("AGENTS.md")
		lacks("AGENTS.md", text, "A first-person Pac-Man clone")
		lacks("AGENTS.md", text, "The game is the `pickman` project")
		lacks("AGENTS.md", text, "/skills/pickman-")
		lacks("AGENTS.md", text, "-arch/SKILL.md")
		lacks("AGENTS.md", text, "-test/SKILL.md")
		lacks("AGENTS.md", text, "game-design.md")
		lacks("AGENTS.md", text, "Every project with code has the same home")
		for _, h in HOMES do
			has("AGENTS.md", text, `\`{h}/\``)
		end
	end)
end)
