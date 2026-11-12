--!strict
-- c0263: merging two branches that both appended to item records (`mergeRef`, behind `sync`, `land`, `fold`, `recombine`,
-- `new raft`, every publishing command) and `remap`'s own merge (`settleRemapRecords`). A
-- record is found by its item id, never by git's pairing of files. Git adapters over `provenance`'s pure rules; they
-- return the failure text and never `fail` (the callers do). Lives apart from main.luau, whose chunk is at Luau's
-- limit of 200 locals.
local fs = require("@lune/fs")
local idsLib = require("./ids")
local provenance = require("./provenance")
local publish = require("./publish")
local sh = require("../lib/sh")

-- c0263: merging two branches that both appended to item records. A record is found by its item id, never by git's
-- pairing of files (git pairs small, templated records across ids and across folder moves).
local function gitLines(args: { string }): { string }
	local out: { string } = {}
	for line in string.gmatch(sh.run("git", args).stdout, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

-- `publish.itemPath` for reading: the layout publish and audit use, plus a retired raft's folder (`rafts/retired/<R-id>/`:
-- `recombine` moves a raft there on its branch while its record may still be published into). Publishing into a retired
-- raft stays refused by `publish.allowed`, which does not use this.
local function itemPathOf(path: string): (string?, string?)
	local id, rel = publish.itemPath(path)
	if id then
		return id, rel
	end
	local plain, swapped = string.gsub(path, "/rafts/retired/", "/rafts/", 1)
	if swapped == 1 then
		return publish.itemPath(plain)
	end
	return nil, nil
end

-- the id of the item whose record `path` is (the item's own folder under a project root, like publish and audit), or nil
local function recordIdOf(path: string): string?
	local id, rel = itemPathOf(path)
	return if rel == "provenance.md" then id else nil
end

-- the paths of `paths` that are item records
local function recordPaths(paths: { string }): { string }
	local out: { string } = {}
	for _, path in paths do
		if recordIdOf(path) then
			table.insert(out, path)
		end
	end
	return out
end

-- The ids of every record either side changed since `base` (git trees or commits; old and new paths of a rename
-- alike, found with `--no-renames`), in the order found (ours', then theirs'), and whether each side changed any.
local function changedRecordIds(base: string, ours: string, theirs: string): ({ string }, boolean, boolean)
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	local flags: { [string]: boolean } = {}
	for _, side in { ours, theirs } do
		for _, path in gitLines({ "diff", "--name-only", "--no-renames", base, side }) do
			local id = recordIdOf(path)
			if id then
				flags[side] = true
				if not seen[id] then
					seen[id] = true
					table.insert(ids, id)
				end
			end
		end
	end
	return ids, flags[ours] == true, flags[theirs] == true
end

type Planned = { id: string, action: string, text: string?, folder: string? }

-- What to do with each record of `ids`: `provenance.settle` over the record of each id at `ours`, `theirs` and `base`
-- (commits or trees), and for a written record the folder of the item's one document in `merged` (the listing of the
-- merged tree). `unmerged` are the ids git left unmerged. Nil and why on the first stop.
local function planRecords(
	ids: { string },
	ours: string,
	theirs: string,
	base: string,
	merged: { string }
): ({ Planned }?, string?)
	local lists: { [string]: { string } } = {}
	for _, tree in { ours, theirs, base } do
		lists[tree] = recordPaths(gitLines({ "ls-tree", "-r", "--name-only", tree }))
	end
	local function recordAt(tree: string, id: string): (string?, string?)
		local path, why = provenance.locate(lists[tree], id)
		if why then
			return nil, why
		end
		return if path then sh.run("git", { "show", `{tree}:{path}` }).stdout else nil, nil
	end
	local plans: { Planned } = {}
	for _, id in ids do
		local own, ownWhy = recordAt(ours, id)
		local their, theirWhy = recordAt(theirs, id)
		local common, commonWhy = recordAt(base, id)
		if ownWhy or theirWhy or commonWhy then
			return nil, ownWhy or theirWhy or commonWhy
		end
		local action, text, problem = provenance.settle(common, own, their)
		if not action then
			return nil, `{id}: {problem}`
		end
		local folder: string? = nil
		if action == "write" then
			for _, path in merged do
				local found = string.match(path, `^(.*/{id})/{id}%.md$`)
				if found and select(2, itemPathOf(path)) == `{id}.md` then
					if folder then
						return nil, `{id} has its document in two places`
					end
					folder = found
				end
			end
			if not folder then
				return nil,
					`{id}: the merge has no document for its record (the item was removed or its id changed: ./zn remap after a compaction, a merge by hand after a renumber)`
			end
		end
		local act: string = action
		table.insert(plans, { id = id, action = act, text = text, folder = folder })
	end
	return plans, nil
end

-- The way through a merge that stopped on a conflict outside the records.
local HAND =
	"merge by hand: git merge origin/main, resolve every conflict except provenance.md (leave the records to the engine), git add the files, then run ./zn sync again: it finishes that merge, uniting the records"

-- A merge of `ref` into this worktree that unites the item records both sides appended to. The merge is made with
-- `--no-commit`; then every record either side changed since the merge base is settled by item id (planRecords): the
-- record goes beside the item's document in the merge (written through the index, and never over a path with
-- uncommitted changes), every other path of that id's record is removed with `git rm -f`, and the merge is committed
-- with the message git prepared. A stop aborts the merge we started (no MERGE_HEAD, the tree as it was), as does any
-- error: the body runs in a `pcall`. Refused first: a merge of a branch `ref` does not contain, a cherry-pick, a
-- revert or a rebase in progress (not ours to finish or abort). A merge in progress of `ref` or of an older commit of it
-- (a hand merge that has only records left) is finished first, never aborted, and then `ref` is merged on top.
-- Returns whether it merged, the failure text, and whether it aborted a merge.
local function mergeRef(ref: string): (boolean, string, boolean)
	local function inProgress(name: string): boolean
		return sh.run("git", { "rev-parse", "-q", "--verify", name }).ok
	end
	local target = sh.trim(sh.run("git", { "rev-parse", "-q", "--verify", ref .. "^{commit}" }).stdout)
	local gitDir = sh.trim(sh.run("git", { "rev-parse", "--absolute-git-dir" }).stdout)
	-- settle the records of the merge in progress and commit it; `ours` says whether we started it (a stop aborts it)
	local function settleAndCommit(detail: string, ours: boolean): (boolean, string)
		-- the advice depends on whose merge this is: ours is aborted by a stop (commit or stash and sync again); the
		-- user's own hand merge stays in progress (git add what they want kept, or git checkout it, then sync again;
		-- a stash would discard the merge)
		local way = if ours
			then "commit or stash them first, then run ./zn sync again"
			else "git add the path to keep it as it is, or git checkout -- it to drop the edit (not git stash: it would discard your merge), then run ./zn sync again"
		local outside = if ours
			then HAND
			else "resolve every conflict except provenance.md, git add the files, then run ./zn sync again: it finishes this merge, uniting the records"
		local function abort(why: string): (boolean, string)
			if ours then
				sh.run("git", { "merge", "--abort" })
			end
			return false, why
		end
		local ran, done, why = pcall(function(): (boolean, string)
			local unmerged: { [string]: boolean } = {}
			local unmergedIds: { string } = {}
			for _, line in gitLines({ "ls-files", "-u" }) do
				local path = string.match(line, "^%d+ %x+ %d\t(.+)$")
				local id = if path then recordIdOf(path) else nil
				if not path or not id then
					return false, `{detail}\n{outside}` -- a conflict outside the records
				end
				unmerged[path] = true
				if not table.find(unmergedIds, id) then
					table.insert(unmergedIds, id)
				end
			end
			local base = sh.trim(sh.run("git", { "merge-base", "HEAD", "MERGE_HEAD" }).stdout)
			local ids, oursChanged, theirsChanged = changedRecordIds(base, "HEAD", "MERGE_HEAD")
			for _, id in unmergedIds do
				if not table.find(ids, id) then
					table.insert(ids, id)
				end
			end
			if #ids > 0 then
				-- ids mean the same item only while both sides number items alike: a compaction on one side reuses them
				local function mapAt(commit: string): string?
					local shown = sh.run("git", { "show", `{commit}:{idsLib.MAP_FILE}` })
					return if shown.ok then shown.stdout else nil
				end
				local crossing = provenance.compactionProblem(
					mapAt(base),
					mapAt("HEAD"),
					mapAt("MERGE_HEAD"),
					oursChanged,
					theirsChanged
				)
				if crossing then
					return false, `{crossing}\n{detail}`
				end
				local index = gitLines({ "ls-files" })
				local plans, problem = planRecords(ids, "HEAD", "MERGE_HEAD", base, index)
				if not plans then
					return false, `{problem}\n{detail}`
				end
				-- never over uncommitted work: a path the merge did not leave unmerged must match the index
				local function dirty(path: string): boolean
					if unmerged[path] then
						return false
					end
					local tracked = sh.run("git", { "ls-files", "--error-unmatch", "--", path }).ok
					if not tracked then
						return fs.isFile(path)
					end
					return not sh.run("git", { "diff", "--quiet", "--", path }).ok
				end
				-- first decide every write and removal and check them all, then apply: a stop leaves the tree as it was
				local writes: { { dest: string, blob: string } } = {}
				local removals: { string } = {}
				for _, plan in plans do
					local dest: string? = nil
					if plan.action == "write" then
						dest = `{plan.folder}/provenance.md`
						local hashed = sh.run("git", { "hash-object", "-w", "--stdin" }, plan.text)
						if not hashed.ok then
							error(hashed.stderr, 0)
						end
						local blob = sh.trim(hashed.stdout)
						local current = sh.run("git", { "rev-parse", "-q", "--verify", `:{dest}` })
						if not (current.ok and sh.trim(current.stdout) == blob) then
							if dirty(dest :: string) then
								return false,
									`{dest} has uncommitted changes the merge would overwrite: {way}\n{detail}`
							end
							table.insert(writes, { dest = dest :: string, blob = blob })
						end
					end
					if plan.action ~= "keep" then
						for _, path in recordPaths(index) do
							if path ~= dest and recordIdOf(path) == plan.id then
								if dirty(path) then
									return false,
										`{path} has uncommitted changes the merge would remove: {way}\n{detail}`
								end
								table.insert(removals, path)
							end
						end
					end
				end
				for _, write in writes do
					sh.must(
						"git",
						{ "update-index", "--add", "--cacheinfo", `100644,{write.blob},{write.dest}` }
					)
					sh.must("git", { "checkout-index", "-f", "--", write.dest })
				end
				for _, path in removals do
					sh.must("git", { "rm", "-q", "-f", "--ignore-unmatch", "--", path })
				end
			end
			if #gitLines({ "ls-files", "-u" }) > 0 then
				return false, detail
			end
			local c = sh.run("git", { "commit", "--no-edit", "-q" })
			if not c.ok then
				return false, c.stderr .. c.stdout
			end
			return true, ""
		end)
		if not ran then
			return abort(`the merge stopped on an error: {done}`)
		end
		if not done then
			return abort(why :: string)
		end
		return true, ""
	end
	local finished = ""
	-- a cherry-pick, a revert or a rebase in progress wins over everything, a hand merge inside it included
	if
		inProgress("CHERRY_PICK_HEAD")
		or inProgress("REVERT_HEAD")
		or fs.isDir(`{gitDir}/rebase-merge`)
		or fs.isDir(`{gitDir}/rebase-apply`)
	then
		return false,
			"a cherry-pick, a revert or a rebase is in progress (nothing was aborted): finish or abort it, then run this again",
			false
	end
	if inProgress("MERGE_HEAD") then
		local head = sh.trim(sh.run("git", { "rev-parse", "MERGE_HEAD" }).stdout)
		if target == "" or not sh.run("git", { "merge-base", "--is-ancestor", head, target }).ok then
			return false,
				"a merge of another branch is in progress (nothing was aborted): finish it (git merge --continue) or abort it (git merge --abort), then run this again",
				false
		end
		-- a hand merge of origin/main, or of an older commit of it: finish it, then merge the newer tip on top
		local ok, why = settleAndCommit(
			`origin/main is being merged by hand: every conflict except provenance.md must be resolved and added first`,
			false
		)
		if not ok then
			return false, why, false
		end
		finished = "your merge was finished and committed; "
	end
	local mergeArgs = { "merge", "--no-commit", "--no-edit", ref }
	local r = sh.run("git", mergeArgs)
	local detail = r.stderr .. r.stdout
	if not inProgress("MERGE_HEAD") then
		return r.ok, if r.ok then "" else finished .. detail, false -- up to date, fast-forwarded, or git refused to start
	end
	local ok, why = settleAndCommit(detail, true)
	if not ok then
		return false, finished .. why, true
	end
	return true, "", false
end

-- c0263: the tree `git merge-tree` wrote for remap, with every item record settled by id (planRecords) over the remapped
-- base, the branch (`HEAD`) and `origin/main`: whether or not git reported a conflict there, and wherever git paired
-- the files. `mt` is the merge-tree output: the tree id, the conflicted-file lines "<mode> <sha> <stage>\t<path>", a
-- blank line, then messages. Nil (and the merge stops, as it always did) when a conflicted path is not a record or a
-- record cannot be settled. Built in the index only (`read-tree`, `update-index`, `write-tree`), then the index is put
-- back to HEAD; the worktree is never touched.
local function settleRemapRecords(mt: string, tree: string, baseTree: string): string?
	local unmerged: { [string]: boolean } = {}
	local unmergedIds: { string } = {}
	local first = true
	for line in string.gmatch(mt .. "\n", "([^\n]*)\n") do
		if first then
			first = false
		elseif line == "" then
			break
		else
			local path = string.match(line, "^%d+ %x+ %d\t(.+)$")
			local id = if path then recordIdOf(path) else nil
			if not id then
				return nil
			end
			if not unmerged[id] then
				unmerged[id] = true
				table.insert(unmergedIds, id)
			end
		end
	end
	local ids = changedRecordIds(baseTree, "HEAD", "origin/main")
	for _, id in unmergedIds do
		if not table.find(ids, id) then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return tree
	end
	local merged = gitLines({ "ls-tree", "-r", "--name-only", tree })
	local plans = planRecords(ids, "HEAD", "origin/main", baseTree, merged)
	if not plans then
		return nil
	end
	for _, plan in plans do
		if plan.action == "keep" and unmerged[plan.id] then
			return nil -- git left a conflicted record that neither side changed: not ours to guess
		end
	end
	local ok, built = pcall(function(): string?
		sh.must("git", { "read-tree", tree })
		for _, plan in plans do
			local target: string? = nil
			if plan.action == "write" then
				target = `{plan.folder}/provenance.md`
				local hashed = sh.run("git", { "hash-object", "-w", "--stdin" }, plan.text)
				if not hashed.ok then
					error(hashed.stderr, 0)
				end
				local blob = sh.trim(hashed.stdout)
				sh.must("git", { "update-index", "--add", "--cacheinfo", `100644,{blob},{target}` })
			end
			if plan.action ~= "keep" then
				for _, path in recordPaths(merged) do
					if path ~= target and recordIdOf(path) == plan.id then
						sh.must("git", { "update-index", "--force-remove", "--", path })
					end
				end
			end
		end
		return sh.trim(sh.must("git", { "write-tree" }))
	end)
	sh.run("git", { "reset", "--quiet", "HEAD" })
	return if ok then built else nil
end

-- c0263: `restack` stopped in a `git rebase` on conflicts. When every unmerged path is an item record, settle each by
-- item id with the union `mergeRef` uses (common = stage 1; "ours" is the layer's side, the commit being replayed, stage 3;
-- "theirs" is main's, the onto side, stage 2: the rows come out base, main, layer as in a merge), write the result where the replayed commit has the record (else where the onto side has it),
-- and stage it. Returns true when nothing is left unmerged (the caller continues the rebase); false with the reason
-- when a path is not a record or a record cannot be united (an id changed on one side), leaving the index as it was.
local function settleRebaseStop(): (boolean, string)
	local byId: { [string]: { [number]: string } } = {}
	local order: { string } = {}
	for _, line in gitLines({ "ls-files", "-u" }) do
		local stage, path = string.match(line, "^%d+ %x+ (%d)\t(.+)$")
		local id = if path then recordIdOf(path :: string) else nil
		if not path or not id then
			return false, `{path or line} is not an item record`
		end
		if not byId[id] then
			byId[id] = {}
			table.insert(order, id)
		end
		byId[id][tonumber(stage :: string) :: number] = path :: string
	end
	if #order == 0 then
		return false, "no conflict is left to settle"
	end
	-- a record the replayed commit (or main) added or moved cleanly is not unmerged: it is at stage 0 under another path of
	-- the same id, and counts as that side's version (the side whose commit has this very blob at that path)
	local zero: { [string]: { [number]: boolean } } = {}
	for _, line in gitLines({ "ls-files", "-s" }) do
		local blob, stage, path = string.match(line, "^%d+ (%x+) (%d)\t(.+)$")
		local id = if path then recordIdOf(path :: string) else nil
		if id and byId[id] and stage == "0" then
			local function at(rev: string): boolean
				local r = sh.run("git", { "rev-parse", "-q", "--verify", `{rev}:{path :: string}` })
				return r.ok and sh.trim(r.stdout) == blob
			end
			if byId[id][3] == nil and at("REBASE_HEAD") then
				byId[id][3] = path :: string
				zero[id] = zero[id] or {}
				zero[id][3] = true
			elseif byId[id][2] == nil and at("HEAD") then
				byId[id][2] = path :: string
				zero[id] = zero[id] or {}
				zero[id][2] = true
			end
		end
	end
	local function text(id: string, stage: number, paths: { [number]: string }): string?
		local path = paths[stage]
		if not path then
			return nil
		end
		local at = if zero[id] and zero[id][stage] then 0 else stage
		local shown = sh.run("git", { "show", `:{at}:{path}` })
		return if shown.ok then shown.stdout else nil
	end
	local plans: { { id: string, action: string, dest: string?, blob: string?, paths: { string } } } = {}
	for _, id in order do
		local paths = byId[id]
		local action, united, why =
			provenance.settle(text(id, 1, paths), text(id, 3, paths), text(id, 2, paths), true)
		if not action then
			return false, `{id}: {why}`
		end
		local all: { string } = {}
		for _, stage in { 1, 2, 3 } do
			if paths[stage] and not table.find(all, paths[stage]) then
				table.insert(all, paths[stage])
			end
		end
		local plan = { id = id, action = action, dest = nil :: string?, blob = nil :: string?, paths = all }
		if action == "write" then
			plan.dest = paths[3] or paths[2] or paths[1]
			local hashed = sh.run("git", { "hash-object", "-w", "--stdin" }, united :: string)
			if not hashed.ok then
				return false, hashed.stderr
			end
			plan.blob = sh.trim(hashed.stdout)
		end
		table.insert(plans, plan)
	end
	for _, plan in plans do
		for _, path in plan.paths do
			if path ~= plan.dest then
				sh.must("git", { "rm", "-q", "-f", "--ignore-unmatch", "--", path })
			end
		end
		if plan.dest then
			sh.must("git", { "update-index", "--add", "--cacheinfo", `100644,{plan.blob},{plan.dest}` })
			sh.must("git", { "checkout-index", "-f", "--", plan.dest })
		end
	end
	if #gitLines({ "ls-files", "-u" }) > 0 then
		return false, "a conflict is left after the records were settled"
	end
	return true, ""
end

return {
	mergeRef = mergeRef,
	settleRebaseStop = settleRebaseStop,
	settleRemapRecords = settleRemapRecords,
}
