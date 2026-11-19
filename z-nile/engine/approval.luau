--!strict
-- Reads an issue's contract and its approval.md. Writes nothing: `approve` commits the text this returns.
-- Specs are read from the issue's acceptance/ while that directory holds any, and otherwise from the
-- promoted tree (`projects.promotedDir`), under the same relative names.

local contract = require("./contract")
local fs = require("@lune/fs")
local guesses = require("./guesses")
local projects = require("./projects")
local store = require("./store")

local approval = {}

local function rooted(root: string, rel: string): string
	if root == "." or root == "" then
		return rel
	end
	return `{root}/{rel}`
end

-- Every *.spec.luau under `dir` (repo-relative, under `root`), as path relative to `dir` -> text, sorted walk; and their
-- repo-relative paths appended to `paths`.
local function walk(root: string, dir: string, prefix: string, specs: { [string]: string }, paths: { string })
	local base = rooted(root, dir)
	if not fs.isDir(base) then
		return
	end
	local names = fs.readDir(base)
	table.sort(names)
	for _, name in names do
		if name ~= "." and name ~= ".." then
			local rel = if prefix == "" then name else `{prefix}/{name}`
			local path = `{dir}/{name}`
			local full = rooted(root, path)
			if fs.isDir(full) then
				walk(root, path, rel, specs, paths)
			elseif fs.isFile(full) and string.match(name, "%.spec%.luau$") then
				specs[rel] = fs.readFile(full)
				table.insert(paths, path)
			end
		end
	end
end

-- The contract parts, and the repo-relative paths of the files that make them (for a dirty check): the folder as it is
-- on disk, read through approval.partsOf, the one rule for which files make the contract.
function approval.collect(root: string, item: store.Item): (contract.Parts?, { string }, string?)
	local paths = { item.doc }
	local files: { [string]: string } = {}
	local docPath = rooted(root, item.doc)
	files[`{item.id}.md`] = if fs.isFile(docPath) then fs.readFile(docPath) else ""
	local checkRel = `{item.dir}/check.sh`
	if fs.isFile(rooted(root, checkRel)) then
		files["check.sh"] = fs.readFile(rooted(root, checkRel))
		table.insert(paths, checkRel)
	end
	local mine: { [string]: string } = {}
	walk(root, `{item.dir}/acceptance`, "", mine, paths)
	local promoted: { [string]: string }? = nil
	if next(mine) ~= nil then
		for rel, text in mine do
			files[`acceptance/{rel}`] = text
		end
	else
		local base = if root == "" then "." else root
		local found: { [string]: string } = {}
		walk(root, projects.promotedDir(projects.load(base), item.root, item.id), "", found, paths)
		promoted = found
	end
	local guessRel = `{item.dir}/{guesses.FILE}`
	local guessPath = rooted(root, guessRel)
	if fs.isFile(guessPath) then
		files[guesses.FILE] = fs.readFile(guessPath)
		table.insert(paths, guessRel)
	end
	local parts, err = approval.partsOf(item.id, files, promoted)
	if not parts then
		return nil,
			paths,
			if err and string.sub(err, 1, #guesses.FILE) == guesses.FILE then `{item.dir}/{err}` else err
	end
	return parts, paths, nil
end

-- Why an approval does not hold, in the short form `done`, `finish` and `work next` print (f0399): "no approval",
-- "changed: <parts>" or the problem; nil when it holds.
function approval.shortOf(parts: contract.Parts, approvalText: string?): string?
	if not approvalText then
		return "no approval"
	end
	local rows, perr = contract.parse(approvalText)
	if not rows then
		return `approval.md does not parse: {perr}`
	end
	local changed = contract.changed(rows[#rows], parts)
	if #changed == 0 then
		return nil
	end
	return `changed: {table.concat(changed, ", ")}`
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

-- The refusal from texts `ready` and `work next` both already have. `required` is ready's rule (a missing
-- approval refuses). done and land leave an issue with no approval.md alone.
function approval.reasonOf(
	id: string,
	fileRel: string,
	parts: contract.Parts,
	approvalText: string?,
	required: boolean
): string?
	if not approvalText then
		if not required then
			return nil
		end
		return `{id} has no approval: run ./zn approve {id} in a terminal, from anywhere in the checkout. This is a one-time step for an item prepared before approval.`
	end
	local rows, perr = contract.parse(approvalText)
	if not rows then
		return `{id}: {fileRel} does not parse: {perr}`
	end
	local changed = contract.changed(rows[#rows], parts)
	if #changed == 0 then
		return nil
	end
	return `{id}'s contract changed since approval: {table.concat(changed, ", ")}. Run ./zn approve {id} again.`
end

-- The refusal, naming the issue. `required` is ready's rule (a missing approval refuses). done and land
-- leave an issue with no approval.md alone: nothing already active or done is sent back for one.
function approval.refusal(root: string, item: store.Item, required: boolean): string?
	local parts, _, err = approval.collect(root, item)
	if not parts then
		return `{item.id}: {err}`
	end
	local path = rooted(root, approval.file(item))
	local text = if fs.isFile(path) then fs.readFile(path) else nil
	return approval.reasonOf(item.id, approval.file(item), parts, text, required)
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

-- d0298: the contract parts of an issue from a folder view (`files`: path relative to its folder -> text, as git
-- tracks it), its acceptance specs from `acceptance/`, or else from `promoted` (path relative to the promoted folder).
-- readycheck.reason and workread's approval loop build the same parts from the facts they already hold (a Member's
-- files, its guesses parsed once): a change to what a contract reads changes all three (review 001 F3).
function approval.partsOf(
	id: string,
	files: { [string]: string },
	promoted: { [string]: string }?
): (contract.Parts?, string?)
	local specs: { [string]: string } = {}
	local found = false
	for rel, text in files do
		local name = string.match(rel, "^acceptance/(.+%.spec%.luau)$")
		if name then
			specs[name] = text
			found = true
		end
	end
	if not found and promoted then
		for rel, text in promoted do
			if string.match(rel, "%.spec%.luau$") then
				specs[rel] = text
			end
		end
	end
	local guessText = files[guesses.FILE]
	if guessText then
		local _, problem = guesses.parse(guessText)
		if problem then
			return nil, `{guesses.FILE}: {problem}`
		end
	end
	return contract.build(files[`{id}.md`] or "", files["check.sh"] or "", specs, guessText)
end

-- d0298: how approval.md's last row stands against `parts`: "holds" (the whole contract), "guesses" (it differs only in
-- the guesses part, a guess recorded since approval, which a ./zn ready outside the dispatcher lets through, f0399) or
-- "stale" (any other difference, or a text that does not parse). The one reader of that rule: readycheck.reason and
-- keepRecords both ask it.
function approval.standing(text: string, parts: contract.Parts): string
	local rows = contract.parse(text)
	if not rows or #rows == 0 then
		return "stale"
	end
	local diff = contract.changed(rows[#rows], parts)
	if #diff == 0 then
		return "holds"
	end
	if #diff == 1 and diff[1] == "guesses" then
		return "guesses"
	end
	return "stale"
end

-- d0298: approval.md's text with its last row re-recorded for `parts` (same when and who, the new parts), or nil with
-- why when it does not parse. `standing` is what the row was before the rewrite: "holds" gets the new hash and every
-- new part hash; "guesses" gets every new part hash except guesses, whose recorded hash stays (the guess stays
-- unapproved), and keeps its old `hash`: it cannot be recomputed for the guesses text that was approved, and an old
-- value equals no current contract, so contract.changed falls through to the parts and names only guesses, as before.
-- One state answers differently afterwards: if the guess added since the approval is later removed, the row reads
-- stale where it would have held again, because the kept hash is not the new contract's. It refuses, never accepts,
-- and f0399's guessesKept refuses a removed guess at approve, finish and done anyway (review 001 F1).
function approval.reseal(text: string, parts: contract.Parts, standing: string): (string?, string?)
	local rows, err = contract.parse(text)
	if not rows then
		return nil, err
	end
	local last = rows[#rows]
	local hashes = contract.partHashes(parts)
	local hash = contract.hash(parts)
	if standing == "guesses" then
		hashes.guesses = last.parts.guesses
		hash = last.hash
	end
	rows[#rows] = { when = last.when, who = last.who, hash = hash, parts = hashes }
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
