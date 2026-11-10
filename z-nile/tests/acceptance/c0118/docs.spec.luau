--!strict
-- c0118 AC5: the zz-rules board row and the README say what the new board does, in the Design's words, and the old
-- row's pinned words stay (the views, -O; the artifact left with c0172).
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

-- the spec runs from its project's home: the checkout's own files are read from the top (c0120)
local process = require("@lune/process")
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function boardRow(): string
	local row = ""
	for line in string.gmatch(fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`), "[^\n]+") do
		if string.sub(line, 1, 10) == "| board | " then
			row = line
		end
	end
	return row
end
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0118 board docs", function(it)
	it("the board row describes tabs, columns, bands, the done window, the card and both charts", function()
		local row = boardRow()
		t.expect(row ~= "").toBe(true)
		for _, phrase in
			{
				"One tab per project in `z-nile/projects.toml`, on the left, the first selected (c0118)",
				"every view shows the selected project only",
				"It opens on Board",
				"ticket (`new`), design (`preparing`), raft (`prepared`)",
				"ready (readied, in `active/`, and its raft's branch has no commit since that ready)",
				"run (its raft's branch `<R-id>-…`, local or on origin, has a commit after its latest ready)",
				"done (in `done/`), each raft a band behind its members",
				"24 hours by default, from 1 hour to 30 days",
				"counted back from the page's as-of time (HEAD's commit time)",
				"PR and checks are live only on the served board (c0121)",
				"90 days by default, 30 days, 1 year or all history",
				"each file once",
				"a row with no model is the unrecorded series",
			}
		do
			if not has(row, phrase) then
				error(`the board row lacks: {phrase}`)
			end
		end
	end)

	it("the old row's words stay: the views, Stats and -O", function()
		local row = boardRow()
		for _, phrase in
			{
				"Views Rafts and Issues",
				"not a third view",
				"unless `-O`",
				"`./zn board [--out PATH] [-O]`",
			}
		do
			if not has(row, phrase) then
				error(`the board row lost: {phrase}`)
			end
		end
	end)

	it("the README draws the built board and names the served one as planned", function()
		local text = fs.readFile(`{TOP}/z-nile/README.md`)
		t.expect(has(text, 'board["board: ./zn board, a tab per project"]')).toBe(true)
		t.expect(has(text, "new board c0118, planned")).toBe(false)
		t.expect(has(text, "`./zn board --serve` (c0121) serves the same page live")).toBe(true)
	end)

	-- design review 013 F3: the board spec builds the page from every project's tracker and takes over 2 s, so it keeps
	-- a line per registered project (c0165's rule); registering a project without its lines turns this red.
	it(
		"the board spec declares both tracker folders of every registered project, the registry and the map",
		function()
			local reg = process.exec("lune", { "run", "z-nile/roots", "--", "--projects" }, { cwd = TOP })
			t.expect(reg.ok).toBe(true)
			local have: { [string]: boolean } = {}
			for line in string.gmatch(fs.readFile(`{TOP}/z-nile/tests/inputs.tsv`), "[^\n]+") do
				have[line] = true
			end
			local missing: { string } = {}
			local projects = 0
			for line in string.gmatch(reg.stdout, "[^\n]+") do
				local trackerRoot = string.match(line, "^[^\t]+\t[^\t]+\t([^\t]+)$")
				if trackerRoot then
					projects += 1
					for _, kind in { "issues/", "rafts/" } do
						local want = `tests/tooling/board.spec.luau\t{trackerRoot}/{kind}`
						if not have[want] then
							table.insert(missing, want)
						end
					end
				end
			end
			for _, file in { "z-nile/projects.toml", "z-nile/compaction.txt" } do
				local want = `tests/tooling/board.spec.luau\t{file}`
				if not have[want] then
					table.insert(missing, want)
				end
			end
			t.expect(projects > 1).toBe(true)
			t.expect(table.concat(missing, "\n")).toBe("")
		end
	)
end)
