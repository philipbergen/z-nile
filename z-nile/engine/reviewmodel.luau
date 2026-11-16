--!strict
-- c0306: which models count as review models, and the record of a review's model (two stamped lines in the review
-- file). Pure: texts in, texts or a refusal out. The list is code (KINDS), never read from .models.toml, so a role
-- or fallback change to another id of the same kind refuses nothing.

local reviewmodel = {}

-- A kind is an id prefix, plain (no pattern). `effort` is the one effort that kind needs, when it needs one.
export type Kind = { prefix: string, effort: string? }

reviewmodel.KINDS = {
	{ prefix = "claude-opus-" },
	{ prefix = "claude-fable-" },
	{ prefix = "kimi-code-k3" },
	{ prefix = "grok-", effort = "xhigh" },
} :: { Kind }

-- The front-matter line the tool writes at a claim and at a raft's creation: `reviews: judged`.
reviewmodel.MARK = "judged"

-- How far down a review file the record lines may sit (c0248's Commit: and Patch: share the rule).
local HEAD_LINES = 12

local function starts(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

-- True when the id is of a review kind, at the effort that kind needs.
function reviewmodel.ok(model: string, effort: string?): boolean
	for _, kind in reviewmodel.KINDS do
		if starts(model, kind.prefix) then
			return kind.effort == nil or effort == kind.effort
		end
	end
	return false
end

function reviewmodel.describe(): string
	local parts: { string } = {}
	for _, kind in reviewmodel.KINDS do
		local part = `{kind.prefix}*`
		if kind.effort then
			part ..= ` at effort {kind.effort}`
		end
		table.insert(parts, part)
	end
	return table.concat(parts, ", ")
end

-- The recorded model and effort: the first `Model:` and `Effort:` lines within the first 12 lines. A `Model:` line
-- with no id reads as "" (a record that fails), a missing line as nil.
function reviewmodel.read(text: string): (string?, string?)
	local model: string? = nil
	local effort: string? = nil
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		if n > HEAD_LINES then
			break
		end
		local m = string.match(line, "^Model:%s*(.-)%s*$")
		if m and model == nil then
			model = m
		end
		local e = string.match(line, "^Effort:%s*(.-)%s*$")
		if e and effort == nil then
			effort = e
		end
	end
	return model, effort
end

-- c0251: the longest reason a `Fallback:` line carries.
reviewmodel.FALLBACK_MAX = 120

-- The recorded fallback reason: the first `Fallback:` line within the first 12 lines (the same window as `read`), or nil
-- when there is none or its reason is empty. The one reader of the line (the dispatcher's supersede rule and the board).
function reviewmodel.fallbackOf(text: string): string?
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		if n > HEAD_LINES then
			break
		end
		local f = string.match(line, "^Fallback:%s*(.-)%s*$")
		if f then
			return if f == "" then nil else f
		end
	end
	return nil
end

-- The text with `Model:` (and `Effort:`, then `Fallback:` when given) prepended, or nil and the refusal when it already
-- records a model or the reason is not one short line.
function reviewmodel.stamp(
	text: string,
	model: string,
	effort: string?,
	fallback: string?
): (string?, string?)
	local had = reviewmodel.read(text)
	if had ~= nil then
		return nil, `already records {had}: a review is recorded once; run a new round`
	end
	if
		fallback ~= nil
		and (string.find(fallback, "\n", 1, true) or #fallback > reviewmodel.FALLBACK_MAX or fallback == "")
	then
		return nil,
			`has a fallback reason that is not one line of at most {reviewmodel.FALLBACK_MAX} characters`
	end
	local head = `Model: {model}\n`
	if effort and effort ~= "" then
		head ..= `Effort: {effort}\n`
	end
	if fallback then
		head ..= `Fallback: {fallback}\n`
	end
	return head .. text, nil
end

-- True when the front matter carries the mark.
function reviewmodel.judged(front: { [string]: string }): boolean
	return front.reviews == reviewmodel.MARK
end

local function number(name: string, pattern: string): number?
	local n = string.match(name, pattern)
	return if n then tonumber(n) else nil
end

-- The names (of a folder) the kind judges, by round then name: design and coherence reviews are
-- `design-review-NNN.md`, a code review `review-NNN.md` and `final-review-NNN.md`. Never a stream review, refute or harvest.
function reviewmodel.files(names: { string }, kind: string): { string }
	local out: { string } = {}
	for _, name in names do
		local hit = if kind == "code"
			then number(name, "^review%-(%d+)%.md$") or number(name, "^final%-review%-(%d+)%.md$")
			else number(name, "^design%-review%-(%d+)%.md$")
		if hit then
			table.insert(out, name)
		end
	end
	table.sort(out, function(a: string, b: string): boolean
		local na = number(a, "(%d+)%.md$") or 0
		local nb = number(b, "(%d+)%.md$") or 0
		if na ~= nb then
			return na < nb
		end
		return a < b
	end)
	return out
end

-- The newest round of each kind the command judges, per folder (F2: a later round supersedes an earlier one):
-- the newest `design-review-NNN.md`; for the code kind the newest `review-NNN.md` and the newest `final-review-NNN.md`,
-- apart. `names` are the folder's files; the result is in file order (review before final).
function reviewmodel.newest(names: { string }, kind: string): { string }
	-- c0251: an idea challenge is `idea-review-NNN.md`; a stream review is `stream-review-<id>-NNN.md`, one line of rounds per layer
	if kind == "idea" or kind == "stream" then
		local best: { [string]: number } = {}
		local bestName: { [string]: string } = {}
		for _, name in names do
			local id: string?, n: number?
			if kind == "idea" then
				id, n = "", number(name, "^idea%-review%-(%d+)%.md$")
			else
				local layer, round = string.match(name, "^stream%-review%-(.+)%-(%d+)%.md$")
				id, n = layer, tonumber(round)
			end
			if id and n and n > (best[id] or -1) then
				best[id], bestName[id] = n, name
			end
		end
		local ids: { string } = {}
		for id in bestName do
			table.insert(ids, id)
		end
		table.sort(ids)
		local out: { string } = {}
		for _, id in ids do
			table.insert(out, bestName[id])
		end
		return out
	end
	local groups: { { string } } = if kind == "code"
		then { { "^review%-(%d+)%.md$" }, { "^final%-review%-(%d+)%.md$" } }
		else { { "^design%-review%-(%d+)%.md$" } }
	local out: { string } = {}
	for _, g in groups do
		local best, bestName = -1, nil
		for _, name in names do
			local n = number(name, g[1])
			if n and n > best then
				best, bestName = n, name
			end
		end
		if bestName then
			table.insert(out, bestName)
		end
	end
	return out
end

-- True when a review's text is one the judge refuses: no `Model:` line, an empty one, or a model that is not a review model.
function reviewmodel.refused(text: string): boolean
	local model, effort = reviewmodel.read(text)
	return model == nil or not reviewmodel.ok(model, effort)
end

-- The mode `./zn dispatch zz-review` takes for a review file: from its kind and its name.
local function modeOf(kind: string, name: string): string
	if kind == "code" then
		return if string.sub(name, 1, 6) == "final-" then "final" else "code"
	end
	return if kind == "coherence" then "raft" else "design"
end

-- The refusal for the first file of `kind` in `files` (name -> text) that is not on a review model, or nil. The ways
-- out are the ones that work from where the file is: always a new round on a review model; for a design or coherence
-- review that records no `Model:` line also the spend that records it (an off-model record is recorded once, so it has
-- only the new round); a coherence review or a member's design review (`onOrigin`) is on origin/main, so its way out is
-- made in a worktree and lands by pull request; a code or final review is committed, so its new round is committed with
-- `./zn commit --phase code-review`.
function reviewmodel.problem(
	files: { [string]: string },
	kind: string,
	owner: string,
	onOrigin: boolean?
): string?
	local names: { string } = {}
	for name in files do
		table.insert(names, name)
	end
	for _, name in reviewmodel.newest(names, kind) do
		local model, effort = reviewmodel.read(files[name])
		local recorded = ""
		if model == nil then
			recorded = "no `Model:` line"
		elseif reviewmodel.ok(model, effort) then
			continue
		else
			recorded = `{model} at effort {effort or "none"}`
			if model == "" then
				recorded = "an empty `Model:` line"
			end
		end
		local stem = (string.gsub(name, "%.md$", ""))
		local again = `run the round again on a review model (./zn dispatch zz-review {owner} --mode {modeOf(
			kind,
			name
		)}, or a fresh subagent on that role's model)`
		local ways: string
		if kind == "code" then
			ways =
				`{again} and commit it with ./zn commit -m "{owner}: review-NNN" --phase code-review --model <id> --effort <level>`
		elseif onOrigin and kind ~= "coherence" then
			-- a grouped member's design review is on origin/main, and a new round changes the member's design record, which
			-- ready then refuses as changed since grouped: the member leaves its raft, is redone in its prep, and is folded back
			ways =
				`take {owner} out of its raft (./zn unfold <R-id> {owner}, in a rafting worktree), run the round again on a review model in its prep (z-design: ./zn dispatch zz-review {owner} --mode {modeOf(
					kind,
					name
				)}, or a fresh subagent on that role's model) and record it with ./zn spend {owner} --phase design-review --note design-review-NNN --model <id> --effort <level>, land that, then fold it back with ./zn fold <R-id> {owner}, which makes a new record (a raft of several issues then needs a new coherence review)`
		else
			ways = again
			if model == nil then
				ways ..= `, or if it did run on one, record it: ./zn spend {owner} --phase design-review --note {stem} --model <id> --effort <level>, then commit the file`
			end
			if kind == "coherence" or onOrigin then
				ways ..= " (this review is on origin/main: either way out is made in a worktree and lands by pull request)"
			end
		end
		return `{owner}: {name} records {recorded}, which is not a review model (review models: {reviewmodel.describe()}). To go on, {ways}`
	end
	return nil
end

-- c0251: a kind's place in the lifecycle (idea, then design, coherence, code, final). A previous reviewer is one of the
-- highest rank up to the kind being written.
reviewmodel.RANK = { design = 1, coherence = 2, code = 3, final = 4 } :: { [string]: number }

-- The rank and round of a review file in a folder of `kind` (design: an issue's; coherence: a raft's own; code: a member's
-- or a raft's code and final reviews), or nil for any other name.
local function rankOf(kind: string, name: string): (number?, number?)
	if kind == "code" then
		local c = number(name, "^review%-(%d+)%.md$")
		if c then
			return reviewmodel.RANK.code, c
		end
		local f = number(name, "^final%-review%-(%d+)%.md$")
		if f then
			return reviewmodel.RANK.final, f
		end
		return nil, nil
	end
	local d = number(name, "^design%-review%-(%d+)%.md$")
	if d then
		return reviewmodel.RANK[kind], d
	end
	return nil, nil
end

-- The models of the previous round. `folders` is each folder's kind and its review files (name -> text); `upto` the rank
-- of the kind being written. Files that record no model are skipped; a refused or flagged round counts. The top rank is
-- the highest rank up to `upto` that any folder holds. In each folder (an entry of `folders`) the newest round at that
-- rank is a previous reviewer: round numbers are never compared between folders (c0248 numbers each layer's reviews from
-- 001). Bare ids, each once, in folder order.
function reviewmodel.priorsOf(
	folders: { { kind: string, files: { [string]: string } } },
	upto: number
): { string }
	type Hit = { folder: number, rank: number, round: number, model: string }
	local hits: { Hit } = {}
	local top = 0
	for i, folder in folders do
		for name, text in folder.files do
			local rank, round = rankOf(folder.kind, name)
			if rank ~= nil and round ~= nil and rank <= upto then
				local model = reviewmodel.read(text)
				if model ~= nil and model ~= "" then
					table.insert(hits, {
						folder = i,
						rank = rank,
						round = round,
						model = (string.gsub(model, "%[[^%[%]]*%]$", "")),
					})
					top = math.max(top, rank)
				end
			end
		end
	end
	local newest: { [number]: Hit } = {}
	for _, hit in hits do
		local had = newest[hit.folder]
		if hit.rank == top and (had == nil or hit.round > had.round) then
			newest[hit.folder] = hit
		end
	end
	local out: { string } = {}
	for i = 1, #folders do
		local hit = newest[i]
		if hit and not table.find(out, hit.model) then
			table.insert(out, hit.model)
		end
	end
	return out
end

return reviewmodel
