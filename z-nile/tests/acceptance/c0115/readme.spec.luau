--!strict
-- c0115 AC9: z-nile/README.md opens (right after its title) with a mermaid picture of the five parts: the tracker,
-- the skills, the dispatcher, .models.toml and the board. Every z- or zz- skill it draws exists in z-nile/skills, or
-- its node says `planned`, and the unbuilt parts carry their issue: z-raft (c0116), the dispatcher and .models.toml
-- (c0117), the new board (c0118). A short account of the five parts follows, then every skill folder by name, and
-- the three design checklists by path, each of which exists. Reads the real tree.
local process = require("@lune/process")
local realfs = require("@lune/fs")
-- c0115 runs from its project's home, z-nile/ (c0120): every path this spec reads is the repository's, from its top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function top(p: string): string
	return if string.sub(p, 1, 1) == "/" then p else `{TOP}/{p}`
end
local fs = {
	readFile = function(p: string): string
		return realfs.readFile(top(p))
	end,
	isFile = function(p: string): boolean
		return realfs.isFile(top(p))
	end,
	isDir = function(p: string): boolean
		return realfs.isDir(top(p))
	end,
	readDir = function(p: string): { string }
		return realfs.readDir(top(p))
	end,
}
local t = require("@tests/lib/t")

local README = "z-nile/README.md"
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function at(text: string, needle: string, where: string)
	if not has(text, needle) then
		error(`{where} is missing: {needle}`, 2)
	end
end
-- the first fenced block, after the title and blank lines only; errors when anything else comes first
local function picture(text: string): string
	local ls = string.split(text, "\n")
	t.expect(ls[1]).toBe("# z-nile")
	local i = 2
	while ls[i] == "" do
		i += 1
	end
	if ls[i] ~= "```mermaid" then
		error(`the first thing after the title is not a mermaid block: {ls[i]}`, 2)
	end
	local out = {}
	i += 1
	while ls[i] ~= nil and ls[i] ~= "```" do
		table.insert(out, ls[i])
		i += 1
	end
	if ls[i] == nil then
		error("the mermaid block is never closed", 2)
	end
	return table.concat(out, "\n")
end
local function folders(base: string): { string }
	local out = {}
	if fs.isDir(base) then
		for _, name in fs.readDir(base) do
			if fs.isFile(`{base}/{name}/SKILL.md`) then
				table.insert(out, name)
			end
		end
	end
	table.sort(out)
	return out
end

return t.spec("c0115 the z-nile README opens with the picture", function(it)
	it("opens with a mermaid block that draws the five parts", function()
		local pic = picture(fs.readFile(README))
		for _, part in { "tracker", "skills", "dispatcher", ".models.toml", "board" } do
			at(pic, part, "the picture")
		end
		at(pic, "flowchart", "the picture")
	end)

	it("every z- and zz- skill in the picture exists, or its node says planned, with its issue", function()
		local pic = picture(fs.readFile(README))
		local seen = 0
		-- every z-/zz- token anywhere in the block, in whatever node shape, must sit inside a quoted label ("…"), and
		-- that label alone decides: a skill with no folder needs "(<issue>, planned)" in its own label
		for line in string.gmatch(pic, "[^\n]+") do
			local labels: { { number } } = {}
			local from = 1
			while true do
				local a = string.find(line, '"', from, true)
				if not a then
					break
				end
				local b = string.find(line, '"', (a :: number) + 1, true)
				if not b then
					error(`an unclosed label: {line}`)
				end
				table.insert(labels, { a :: number, b :: number })
				from = (b :: number) + 1
			end
			local pos = 1
			while true do
				local a, b, name = string.find(line, "(z+%-[%a][%w%-]*)", pos)
				if not a then
					break
				end
				pos = (b :: number) + 1
				local prev = string.sub(line, (a :: number) - 1, (a :: number) - 1)
				if
					name == "z-nile"
					or not string.match(name :: string, "^zz?%-")
					or string.match(prev, "[%w_]")
				then
					continue -- the project's name, or part of another word (a node id such as zticket is no token)
				end
				local label: string? = nil
				for _, l in labels do
					if l[1] < (a :: number) and (b :: number) < l[2] then
						label = string.sub(line, l[1] + 1, l[2] - 1)
					end
				end
				if not label then
					error(`{name} is drawn outside a quoted label: {line}`)
				end
				seen += 1
				if not fs.isFile(`z-nile/skills/{name}/SKILL.md`) then
					if not has(label :: string, `{name} (`) or not has(label :: string, "planned)") then
						error(
							`{name} is drawn but has no folder and no (issue, planned) in its label: {label}`
						)
					end
				end
			end
		end
		t.expect(seen >= 10).toBe(true)
		at(pic, "z-raft (c0116, planned)", "the picture")
		at(pic, "dispatcher (c0117, planned)", "the picture")
		at(pic, ".models.toml (c0117, planned)", "the picture")
		at(pic, 'board["board: ./zn board, a tab per project"]', "the picture") -- c0118 override: the board is built
	end)

	it("a short account of the five parts follows the picture", function()
		local text = fs.readFile(README)
		local a = string.find(text, "\n## The five parts\n", 1, true)
		t.expect(a ~= nil).toBe(true)
		local part =
			string.sub(text, a :: number, (string.find(text, "\n## ", (a :: number) + 5, true) or 0) - 1)
		for _, bullet in
			{
				"\n- **The tracker.**",
				"\n- **The skills.**",
				"\n- **The dispatcher** (c0117, planned).",
				"\n- **`.models.toml`** (c0117, planned).",
				"\n- **The board.**",
			}
		do
			at(part, bullet, "The five parts")
		end
		at(part, "`./zn skills`", "The five parts")
	end)

	it("names every skill folder and the three checklists, each of which exists", function()
		local text = fs.readFile(README)
		for _, base in { "z-nile/skills", "pickman/skills" } do
			for _, name in folders(base) do
				at(text, `\`{name}\``, "README")
			end
		end
		for _, kind in { "feature", "defect", "chore" } do
			local path = `z-nile/skills/z-design/checklists/{kind}.md`
			at(text, `\`{path}\``, "README")
			t.expect(fs.isFile(path)).toBe(true)
		end
	end)
	it(
		"covers every ask of c0113, which it supersedes: a skill table, the command sequence, the state diagram",
		function()
			local text = fs.readFile(README)
			at(text, "\n## Skills\n| skill | step | what it does |", "README (c0113: a skill table)")
			at(text, "\n## The flow\n", "README (c0113: the command sequence)")
			local diagram = string.match(text, "```mermaid\nstateDiagram%-v2\n(.-)```")
			if not diagram then
				error("README (c0113: the state diagram) has no stateDiagram-v2 block")
			end
			for _, edge in
				{
					"[*] --> new",
					"new --> preparing",
					"preparing --> new: release the claim",
					"preparing --> prepared",
					"prepared --> active",
					"active --> prepared: z-stop",
					"active --> done",
				}
			do
				at(diagram, edge, "README state diagram (c0113)")
			end
			at(text, "`design:` is separate from status", "README (c0113: the separate design field)")
		end
	)
end)
