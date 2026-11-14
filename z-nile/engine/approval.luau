--!strict
-- Reads an issue's contract and its approval.md. Writes nothing: `approve` commits the text this returns.
-- Specs are read from the issue's acceptance/ while that directory holds any, and otherwise from the
-- promoted tree (`projects.promotedDir`), under the same relative names.

local contract = require("./contract")
local fs = require("@lune/fs")
local projects = require("./projects")
local store = require("./store")

local approval = {}

local function rooted(root: string, rel: string): string
	if root == "." or root == "" then
		return rel
	end
	return `{root}/{rel}`
end

local function walk(
	root: string,
	dir: string,
	prefix: string,
	specs: { [string]: string },
	paths: { string }
): boolean
	local base = rooted(root, dir)
	if not fs.isDir(base) then
		return false
	end
	local found = false
	local names = fs.readDir(base)
	table.sort(names)
	for _, name in names do
		if name ~= "." and name ~= ".." then
			local rel = if prefix == "" then name else `{prefix}/{name}`
			local path = `{dir}/{name}`
			local full = rooted(root, path)
			if fs.isDir(full) then
				if walk(root, path, rel, specs, paths) then
					found = true
				end
			elseif fs.isFile(full) and string.match(name, "%.spec%.luau$") then
				specs[rel] = fs.readFile(full)
				table.insert(paths, path)
				found = true
			end
		end
	end
	return found
end

-- The contract parts, and the repo-relative paths of the files that make them (for a dirty check).
function approval.collect(root: string, item: store.Item): (contract.Parts?, { string }, string?)
	local paths = { item.doc }
	local docPath = rooted(root, item.doc)
	local doc = if fs.isFile(docPath) then fs.readFile(docPath) else ""
	local checkRel = `{item.dir}/check.sh`
	local checkPath = rooted(root, checkRel)
	local check = ""
	if fs.isFile(checkPath) then
		check = fs.readFile(checkPath)
		table.insert(paths, checkRel)
	end
	local specs: { [string]: string } = {}
	if not walk(root, `{item.dir}/acceptance`, "", specs, paths) then
		local base = if root == "" then "." else root
		local dest = projects.promotedDir(projects.load(base), item.root, item.id)
		walk(root, dest, "", specs, paths)
	end
	local parts, err = contract.build(doc, check, specs)
	if not parts then
		return nil, paths, err
	end
	return parts, paths, nil
end

function approval.file(item: store.Item): string
	return `{item.dir}/{contract.FILE}`
end

export type Verdict = {
	state: string, -- "none" | "bad" | "holds" | "changed"
	changed: { string },
	row: contract.Row?,
	err: string?,
}

function approval.verdict(root: string, item: store.Item): (Verdict?, string?)
	local parts, _, err = approval.collect(root, item)
	if not parts then
		return nil, err
	end
	local path = rooted(root, approval.file(item))
	if not fs.isFile(path) then
		return { state = "none", changed = {}, row = nil, err = nil }, nil
	end
	local rows, perr = contract.parse(fs.readFile(path))
	if not rows then
		return { state = "bad", changed = {}, row = nil, err = perr }, nil
	end
	local row = rows[#rows]
	local changed = contract.changed(row, parts)
	if #changed == 0 then
		return { state = "holds", changed = {}, row = row, err = nil }, nil
	end
	return { state = "changed", changed = changed, row = row, err = nil }, nil
end

-- The refusal, naming the issue. `required` is ready's rule (a missing approval refuses). done and land
-- leave an issue with no approval.md alone: nothing already active or done is sent back for one.
function approval.refusal(root: string, item: store.Item, required: boolean): string?
	local found, err = approval.verdict(root, item)
	if not found then
		return `{item.id}: {err}`
	end
	if found.state == "none" then
		if not required then
			return nil
		end
		return `{item.id} has no approval: run ./zn approve {item.id} first. This is a one-time step for an item prepared before approval.`
	end
	if found.state == "bad" then
		return `{item.id}: {approval.file(item)} does not parse: {found.err}`
	end
	if found.state == "changed" then
		return `{item.id}'s contract changed since approval: {table.concat(found.changed, ", ")}. Run ./zn approve {item.id} again.`
	end
	return nil
end

-- approval.md with one new row appended. The caller writes and commits only that file.
function approval.append(root: string, item: store.Item, who: string, when: string): (string?, string?)
	local parts, _, err = approval.collect(root, item)
	if not parts then
		return nil, err
	end
	local rows: { contract.Row } = {}
	local path = rooted(root, approval.file(item))
	if fs.isFile(path) then
		local parsed, perr = contract.parse(fs.readFile(path))
		if not parsed then
			return nil, `{approval.file(item)} does not parse: {perr}`
		end
		rows = parsed
	end
	local name = contract.who(who)
	if name == "" then
		return nil, "approve needs a git identity (git config user.name)"
	end
	table.insert(rows, {
		when = when,
		who = name,
		hash = contract.hash(parts),
		parts = contract.partHashes(parts),
	})
	return contract.render(rows), nil
end

function approval.summary(item: store.Item): string
	local path = approval.file(item)
	if not fs.isFile(path) then
		return `Approvals for {item.id}: 0 (re-approvals 0).`
	end
	local rows, err = contract.parse(fs.readFile(path))
	if not rows then
		return `Approvals for {item.id}: unreadable ({err}).`
	end
	return `Approvals for {item.id}: {#rows} (re-approvals {contract.reapprovals(rows)}).`
end

return approval
