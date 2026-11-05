--!strict
-- c0183 AC6: AGENTS.md and z-nile/README.md name the arcade's projects, after the sentences that name pickman (which
-- c0120's docs spec pins and which stay as they are). This spec is promoted, so it pins the rule (each new project's
-- folder is named after the pickman sentence), not today's wording, which later issues may reword (design review 001
-- F3). check.sh's AC6 holds the exact sentences on the day c0183 is done. These specs run from z-nile/: the documents
-- are read from the top.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local NEW = { "arcade", "portal", "snake", "invaders", "asteroids" }

-- every name `form` makes from a new project appears in `text` after `anchor`
local function namedAfter(text: string, anchor: string, form: (string) -> string, where: string)
	local a = string.find(text, anchor, 1, true)
	if not a then
		error(`{where}: missing "{anchor}"`)
	end
	local missing: { string } = {}
	for _, n in NEW do
		if not string.find(text, form(n), a, true) then
			table.insert(missing, form(n))
		end
	end
	t.expect(missing).toEqual({})
end

return t.spec("c0183 the docs name the arcade's projects", function(it)
	it("AC6: AGENTS.md names each new project's folder after the pickman sentence", function()
		namedAfter(
			fs.readFile(`{TOP}/AGENTS.md`),
			"The game is the `pickman` project, in `pickman/`",
			function(n)
				return `\`{n}/\``
			end,
			"AGENTS.md"
		)
	end)

	it("AC6: z-nile/README.md names each new project after 'A game is a project'", function()
		namedAfter(
			fs.readFile(`{TOP}/z-nile/README.md`),
			"A game is a project: pickman is one, in `pickman/`.",
			function(n)
				return `\`{n}\``
			end,
			"README"
		)
	end)
end)
