--!strict
-- Writes a matching approval.md beside a prepared issue in a fixture, so `./zn ready` can succeed.
-- `./zn approve` refuses in the fixture's main checkout and without a terminal, and the engine never
-- approves by itself. The caller commits the files (a seed commit, or its own). This writes nothing
-- for an issue that is not design: ready, has an unruled open-list bullet, or has no check.sh.

local approval = require("@znile/engine/approval")
local contract = require("@znile/engine/contract")
local fs = require("@lune/fs")
local openlist = require("@znile/engine/openlist")
local paths = require("@znile/engine/paths")
local store = require("@znile/engine/store")

local seal = {}

local function hasCheck(text: string): boolean
	for line in string.gmatch(text, "[^\n]+") do
		if string.match(line, '^%s*check "') then
			return true
		end
	end
	return false
end

local function docsUnder(dir: string, rel: string, out: { string })
	local base = if rel == "" then dir else `{dir}/{rel}`
	if not fs.isDir(base) then
		return
	end
	for _, name in fs.readDir(base) do
		if name ~= ".git" and name ~= ".cache" then
			local child = if rel == "" then name else `{rel}/{name}`
			local full = `{dir}/{child}`
			if fs.isDir(full) then
				docsUnder(dir, child, out)
			elseif string.match(child, "/([fdc]%d%d%d%d)/%1%.md$") then
				table.insert(out, child)
			end
		end
	end
end

-- Approval files for backlog issues in `dir` that ready would ask for. Returns how many it wrote.
function seal.stamp(dir: string, who: string?): number
	local name = contract.who(who or "fixture")
	if name == "" then
		return 0
	end
	local when = os.date("!%Y-%m-%dT%H:%M:%SZ") :: string
	local docs: { string } = {}
	docsUnder(dir, "", docs)
	local wrote = 0
	for _, docRel in docs do
		if
			string.find(docRel, "/issues/active/", 1, true) or string.find(docRel, "/issues/done/", 1, true)
		then
			continue
		end
		local id = string.match(docRel, "([fdc]%d%d%d%d)/%.md$") :: string
		local itemDir = string.match(docRel, "^(.*)/[^/]+$") :: string
		local root = paths.rootOf(itemDir)
		if not root then
			continue
		end
		local doc = fs.readFile(`{dir}/{docRel}`)
		if string.match(doc, "\ndesign: ready\n") == nil then
			continue
		end
		if #openlist.pending(doc) > 0 then
			continue
		end
		local checkRel = `{itemDir}/check.sh`
		if not fs.isFile(`{dir}/{checkRel}`) or not hasCheck(fs.readFile(`{dir}/{checkRel}`)) then
			continue
		end
		local item: store.Item = {
			id = id,
			kind = "issue",
			state = "backlog",
			dir = itemDir,
			doc = docRel,
			slug = "",
			root = root,
		}
		local found = approval.verdict(dir, item)
		if found and found.state == "holds" then
			continue
		end
		local text = approval.append(dir, item, name, when)
		if not text then
			continue
		end
		fs.writeFile(`{dir}/{approval.file(item)}`, text)
		wrote += 1
	end
	return wrote
end

return seal
