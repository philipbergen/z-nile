--!strict
-- The texts `./zn ready` already has on disk, as the facts readycheck.reason reads. work next builds the
-- same facts from origin/main. Neither path pushes.

local fs = require("@lune/fs")
local projects = require("./projects")
local raftplan = require("./raftplan")
local readycheck = require("./readycheck")
local statusLib = require("./status")
local store = require("./store")

local readyfacts = {}

local function walk(dir: string, take: (string) -> boolean): { [string]: string }
	local out: { [string]: string } = {}
	local function rec(rel: string)
		local base = if rel == "" then dir else `{dir}/{rel}`
		if not fs.isDir(base) then
			return
		end
		for _, name in fs.readDir(base) do
			if name ~= "." and name ~= ".." then
				local child = if rel == "" then name else `{rel}/{name}`
				local full = `{dir}/{child}`
				if fs.isDir(full) then
					rec(child)
				elseif fs.isFile(full) and take(child) then
					out[child] = fs.readFile(full)
				end
			end
		end
	end
	rec("")
	return out
end

local function promoted(item: store.Item): { [string]: string }
	local dest = projects.promotedDir(projects.load("."), item.root, item.id)
	return walk(dest, function(rel: string): boolean
		return string.match(rel, "%.spec%.luau$") ~= nil
	end)
end

-- The first reason ready would refuse this raft, from the working tree. Nil when it would accept.
function readyfacts.reason(raft: store.Item, members: { store.Item }): string?
	local front = store.readFront(raft.doc)
	local isMember: { [string]: boolean } = {}
	for _, m in members do
		isMember[m.id] = true
	end
	local built: { readycheck.Member } = {}
	for _, m in members do
		local mf = store.readFront(m.doc)
		local files = walk(m.dir, function(rel: string): boolean
			return raftplan.isDesignFile(rel, m.id) or rel == "approval.md"
		end)
		table.insert(built, {
			id = m.id,
			design = mf.design or "",
			doc = if fs.isFile(m.doc) then fs.readFile(m.doc) else "",
			deps = readycheck.deps(mf.depends_on, function(id: string): string
				if isMember[id] then
					return "member"
				end
				local found = store.find(id)
				return if found then found.state else "missing"
			end),
			files = files,
			specs = readycheck.specs(files, promoted(m)),
			approval = files["approval.md"],
			approvalFile = `{m.dir}/approval.md`,
		})
	end
	local files = walk(raft.dir, function(rel: string): boolean
		return rel == "check.sh"
			or string.match(rel, "^design%-review%-%d+%.md$") ~= nil
			or string.match(rel, "^design%-refute%-%d+%.md$") ~= nil
	end)
	local why = readycheck.reason({
		id = raft.id,
		where = raft.state,
		status = statusLib.effective(front, raft.state),
		dir = raft.dir,
		design = front.design or "",
		doc = if fs.isFile(raft.doc) then fs.readFile(raft.doc) else "",
		grouped = front.grouped,
		listed = store.idList(front.issues),
		members = built,
		files = files,
		loaded = true,
	})
	return why
end

return readyfacts
