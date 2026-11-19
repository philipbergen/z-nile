--!strict
-- What a restack must keep of a layer: which copy of the branch holds every commit, a commit's change as a text
-- that survives a clean rebase, and whether a rebuilt layer kept one commit for each commit it held. Pure: texts in,
-- texts out; git stays in main.luau.
local layercommits = {}

-- The two copies of one layer branch, as git answered for them. `sameCommits`: each copy's own commits (from its
-- own first own commit) are one list, by `keepsCommits`. `localStacked`/`remoteStacked`: the base the layer goes
-- onto is an ancestor of that copy.
export type Copies = {
	localSha: string?,
	remoteSha: string?,
	remoteInLocal: boolean,
	localInRemote: boolean,
	sameCommits: boolean,
	localStacked: boolean,
	remoteStacked: boolean,
}

-- Which copy holds every commit of the layer: the one the other is an ancestor of. A rebuilt copy is never an
-- ancestor or a descendant of the copy it replaces, so two copies that are neither but hold the same commits (a
-- restack killed between moving the branch and pushing it, or a clone whose copy is the old one) are one layer on
-- two bases: the copy already on the base, else the local one. Different commits are diverged and refused, since a
-- rebase of either copy would drop the other's.
function layercommits.pickTip(c: Copies): (string?, string?)
	if c.localSha == nil and c.remoteSha == nil then
		return nil, "it has no tip"
	end
	if c.localSha == nil or c.localSha == c.remoteSha then
		return c.remoteSha, nil
	end
	if c.remoteSha == nil or c.remoteInLocal then
		return c.localSha, nil
	end
	if c.localInRemote then
		return c.remoteSha, nil
	end
	if c.sameCommits then
		if c.remoteStacked and not c.localStacked then
			return c.remoteSha, nil
		end
		return c.localSha, nil
	end
	return nil, "the local branch and its origin copy have diverged"
end

export type Commit = { subject: string, change: string }

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

-- A commit's change, from `git diff-tree -p -U0 --binary --full-index --no-renames --no-commit-id -r` of it, as a
-- text a clean rebase leaves alone. Each file's section keeps its mode lines, its changed lines and its binary patch;
-- it drops its header's paths and blob ids (`diff --git`, `index`, `---`, `+++`: a rename on the new base moves the
-- path, a moved base changes the blobs) and cuts each hunk header to `@@` (line numbers and function context move).
-- Only the header loses those lines: a removed line that reads `--- x` is a change. Sections are sorted, since a
-- rename can reorder them. The raft's derived `spend.md` is left out (a restack may take main's copy, c0248).
function layercommits.changeKey(patch: string, raftId: string): string
	local spend = `/{raftId}/spend.md`
	local sections: { string } = {}
	local current: { string }? = nil
	local inHeader = false
	local function close()
		if current then
			table.insert(sections, table.concat(current, "\n"))
		end
		current = nil
	end
	for line in string.gmatch(patch .. "\n", "([^\n]*)\n") do
		if startsWith(line, "diff --git ") then
			close()
			current = if string.sub(line, -#spend) == spend then nil else {}
			inHeader = true
		elseif current then
			local into = current :: { string }
			if startsWith(line, "@@ ") then
				inHeader = false
				table.insert(into, "@@")
			elseif inHeader and startsWith(line, "GIT binary patch") then
				inHeader = false
				table.insert(into, line)
			elseif
				-- the header's blob ids and paths are left out
				not inHeader
				or not (startsWith(line, "index ") or startsWith(line, "--- ") or startsWith(line, "+++ "))
			then
				table.insert(into, line)
			end
		end
	end
	close()
	table.sort(sections)
	return table.concat(sections, "\n\30\n")
end

-- Nil when `after` holds one commit for each commit of `before`, with the same subject and change, in the same
-- order; otherwise what differs, naming the commit.
function layercommits.keepsCommits(before: { Commit }, after: { Commit }): string?
	for i, was in before do
		local now = after[i]
		if not now then
			return `"{was.subject}" is missing after the rebase`
		end
		if now.subject ~= was.subject then
			return `commit {i} was "{was.subject}" and is "{now.subject}" after the rebase`
		end
		if now.change ~= was.change then
			if now.change == "" then
				return `"{was.subject}" is empty on the new base (its change is already there)`
			end
			return `"{was.subject}" changes something else after the rebase`
		end
	end
	if #after > #before then
		return `the rebase made {#after} commits from {#before}`
	end
	return nil
end

return layercommits
