--!strict
-- c0388: the raft and issue folders a checkout holds, for c0042's cli spec, which compares them with the board page.
-- The roots come from the registry (`z-nile/projects.toml` under `top`), never from a list written here: the spec's
-- hand list of two roots went stale when arcade's root got its first raft (R0110). Each registered root's backlog,
-- `active/` and `done/` are read; a folder a root does not have yet is skipped. A retired root holds no items, and
-- `rafts/retired/` is history the page does not show: neither is read. A closed issue (won't do, c0278) keeps its
-- folder but the page drops it, so it is not listed either. A folder with no document is still listed: the page
-- drops it (it adds a folder only with its document), so the case goes red on it as on a broken item or a
-- leftover, which is the point (c0388 G3).
local closing = require("@znile/engine/closing")
local fs = require("@lune/fs")
local projects = require("@znile/engine/projects")
local store = require("@znile/engine/store")

local ondisk = {}

export type Items = { rafts: { string }, issues: { string } }

local STATES = { "", "/active", "/done" }

-- whether the page shows the folder: all but a closed issue (a folder with no document is shown)
local function shown(dir: string, id: string): boolean
	local doc = `{dir}/{id}/{id}.md`
	return not (fs.isFile(doc) and closing.isClosed(store.readFront(doc)))
end

-- the ids of the folders named like a raft (`R0010`) and like an issue (`f0010`, `d0010`, `c0010`), a closed issue
-- left out; the order is not part of the contract
function ondisk.items(top: string): Items
	local out: Items = { rafts = {}, issues = {} }
	local reg = projects.load(top, true)
	for _, root in projects.roots(reg) do
		for _, state in STATES do
			local rafts = `{top}/{root}/rafts{state}`
			if fs.isDir(rafts) then
				for _, name in fs.readDir(rafts) do
					if string.match(name, "^R%d%d%d%d$") then
						table.insert(out.rafts, name)
					end
				end
			end
			local issues = `{top}/{root}/issues{state}`
			if fs.isDir(issues) then
				for _, name in fs.readDir(issues) do
					if string.match(name, "^[fdc]%d%d%d%d$") and shown(issues, name) then
						table.insert(out.issues, name)
					end
				end
			end
		end
	end
	return out
end

return ondisk
