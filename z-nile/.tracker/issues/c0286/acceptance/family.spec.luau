--!strict
-- c0286 AC4 (review 001 F2, F3): the families the user tied into one raft carry readable `tied:` lines on the real
-- tree, and those lines tie exactly each family together. For each family:
--   * a member's document holds at most one `tied:` line, as the line after `id:` (review 001 F7), that
--     raftplan.parseTied reads with no problem, naming exactly the family's other members, sorted;
--   * every member in the backlog with an empty `raft:` and a design that is not ready carries it;
--   * while any member is in the backlog with an empty `raft:`, at least one member carries it (each line names the
--     whole family, so one line connects it: the ties are undirected);
--   * no issue outside the family has a `tied:` line naming one of its members.
-- The families are the ones Implementation step 5 migrates (Behaviour 6, as ruled under Open to the human F1).
-- Reads the real tree, plain reads only, and parses with the one reader of the format.
local fs = require("@lune/fs")
local process = require("@lune/process")
local raftplan = require("@znile/engine/raftplan")
local store = require("@znile/engine/store")
local t = require("@tests/lib/t")

local FAMILIES: { { string } } = {
	{ "c0247", "c0248", "c0250", "c0256", "c0260", "c0262" },
	{ "c0249", "c0251", "c0252", "c0253", "c0254" },
}

-- runs from its project's home, z-nile/: every path this spec reads is the repository's, from its top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

type Doc = { id: string, path: string, state: string, text: string }

-- every issue document of every project root (`<dir>/.tracker/issues/[active/|done/]<id>/<id>.md`), by id
local function allIssues(): { [string]: Doc }
	local out: { [string]: Doc } = {}
	for _, top in fs.readDir(TOP) do
		local issues = `{TOP}/{top}/.tracker/issues`
		-- isDir raises on a path under a plain file, so the top entry is tested first
		if fs.isDir(`{TOP}/{top}`) and fs.isDir(`{TOP}/{top}/.tracker`) and fs.isDir(issues) then
			for _, sub in { { "", "backlog" }, { "active/", "active" }, { "done/", "done" } } do
				local dir = `{issues}/{sub[1]}`
				if fs.isDir(dir) then
					for _, id in fs.readDir(dir) do
						local path = `{dir}{id}/{id}.md`
						if string.match(id, "^[fdc]%d%d%d%d$") and fs.isFile(path) then
							out[id] = { id = id, path = path, state = sub[2], text = fs.readFile(path) }
						end
					end
				end
			end
		end
	end
	return out
end

-- the front matter's lines, in order
local function frontLines(text: string): { string }
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-") or ""
	local out: { string } = {}
	for line in string.gmatch(block, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

local function others(family: { string }, id: string): { string }
	local out: { string } = {}
	for _, m in family do
		if m ~= id then
			table.insert(out, m)
		end
	end
	table.sort(out)
	return out
end

return t.spec("c0286 the tied families carry their tie on the real tree", function(it)
	local docs = allIssues()

	for n, family in FAMILIES do
		it(
			`family {n} ({table.concat(family, ", ")}): readable lines, on every member that must carry one`,
			function()
				local carriers, raftless = 0, 0
				for _, id in family do
					local d = docs[id]
					if d == nil then
						error(`{id} is not in the tree`)
					end
					local lines = frontLines(d.text)
					local at: { number } = {}
					for k, line in lines do
						if string.match(line, "^tied:") then
							table.insert(at, k)
						end
					end
					if #at > 1 then
						error(`{id} has {#at} tied: lines`)
					end
					local front = store.readFront(d.path)
					local open = d.state == "backlog" and (front.raft or "") == ""
					if open then
						raftless += 1
					end
					if #at == 1 then
						carriers += 1
						t.expect(lines[at[1] - 1]).toBe(`id: {id}`)
						local ids, problem = raftplan.parseTied(front.tied)
						t.expect(problem).toBe(nil)
						t.expect(ids).toEqual(others(family, id))
					elseif open and front.design ~= "ready" then
						error(
							`{id} is in the backlog with no raft and design {front.design}, and has no tied: line`
						)
					end
				end
				if raftless > 0 and carriers == 0 then
					error(`no member carries the tie, and {raftless} of them are in the backlog with no raft`)
				end
			end
		)
	end

	it("no issue outside a family names one of its members in tied:", function()
		local familyOf: { [string]: number } = {}
		for n, family in FAMILIES do
			for _, id in family do
				familyOf[id] = n
			end
		end
		for id, d in docs do
			local value = store.readFront(d.path).tied
			if value then
				local ids = raftplan.parseTied(value)
				for _, named in ids do
					if familyOf[named] and familyOf[named] ~= familyOf[id] then
						error(`{id}'s tied: names {named}, a member of family {familyOf[named]}`)
					end
				end
			end
		end
	end)
end)
