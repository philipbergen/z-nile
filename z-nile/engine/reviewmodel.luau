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

-- The text with `Model:` (and `Effort:` when given) prepended, or nil and the refusal when it already records a model.
function reviewmodel.stamp(text: string, model: string, effort: string?): (string?, string?)
	local had = reviewmodel.read(text)
	if had ~= nil then
		return nil, `already records {had}: a review is recorded once; run a new round`
	end
	local head = `Model: {model}\n`
	if effort and effort ~= "" then
		head ..= `Effort: {effort}\n`
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
	for _, name in reviewmodel.files(names, kind) do
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

return reviewmodel
