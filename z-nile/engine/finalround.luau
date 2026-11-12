--!strict
-- The last review round must have run a final-review model (c0261, the user's "Commands refuse"): `./zn status <id>
-- prepared` (the design review round of an item and of a raft) and `./zn done` (the final review of the raft's stack)
-- ask this module. The model of a round is the `model` of its spend row (the dispatcher writes it, an interactive
-- author passes `--model`); it passes when it is of a final-review KIND (models.FINAL_SHAPES: any Opus, kimi k3.1-pro
-- or k3-256k at high or max, any grok model at xhigh), never by exact id, so a model upgrade in .models.toml locks
-- nobody out. An item whose first round predates this module's landing is not held to it. Pure: names, rows and times
-- in, a refusal out; rowsOf takes the reader of spend.md and spend.d, so that metrics and this module share one.
local ledger = require("./ledger")
local models = require("./models")

local finalround = {}

export type Kind = "design" | "final"

local PREFIX = { design = "design-review-", final = "final-review-" } :: { [string]: string }
local PHASE = { design = "design-review", final = "code-review" } :: { [string]: string }

-- The highest round file of the kind among `files`, as (number, stem), or nil: "design-review-003.md" gives 3,
-- "design-review-003". A layer's review-NNN, a stream review, a refute and a harvest are not rounds.
function finalround.lastRound(files: { string }, kind: Kind): (number?, string?)
	local prefix = PREFIX[kind]
	local best: number? = nil
	for _, name in files do
		local digits = string.match(name, "^" .. string.gsub(prefix, "%-", "%%-") .. "(%d+)%.md$")
		local n = if digits then tonumber(digits) else nil
		if n and (best == nil or n > best) then
			best = n
		end
	end
	if best == nil then
		return nil, nil
	end
	return best, `{prefix}{string.format("%03d", best)}`
end

-- Whether a spend row is the record of round `stem` of `owner` (an issue id or a raft id): the phase of its kind and
-- exactly the written subject. A design round of an ISSUE is "design-review-NNN" (what `./zn spend --note` and the
-- dispatcher write); a design round of a RAFT is "<R-id>: design-review-NNN" (`./zn spend <R-id>` prefixes the raft's id
-- when it spreads the row over the members, so no member's own round can stand in for it); the final round is
-- "<R-id>: final-review-NNN" (the line the dispatcher prints for `./zn commit -m`). Another raft's id, a stream review's "<id>: stream-review-NNN"
-- and a later "<id>: final-review-NNN fixes" are not it.
local function isRoundRow(r: ledger.Row, kind: Kind, stem: string, owner: string): boolean
	if r.phase ~= PHASE[kind] then
		return false
	end
	if kind == "design" and string.sub(owner, 1, 1) ~= "R" then
		return r.subject == stem
	end
	return r.subject == `{owner}: {stem}`
end

-- Whether the rule binds an item (c0261): it does when this module has landed on the base (`landedWhen`, the UTC minute
-- "YYYY-MM-DD HH:MM" of the commit that first added it there) and the item's first review row (`firstWhen`, the
-- earliest `when` among its rows of the kind's phase; nil, no row yet) is at or after that minute. The rows' own `when`
-- are content: they survive a squash, a rebase and a round that is still uncommitted, which commit times do not. An
-- older item in flight is never locked out, and nothing is keyed on a calendar date.
function finalround.enforced(firstWhen: string?, landedWhen: string?): boolean
	if landedWhen == nil then
		return false
	end
	return firstWhen == nil or string.sub(firstWhen, 1, 16) >= string.sub(landedWhen, 1, 16)
end

-- The earliest `when` among the rows of the kind's phase, or nil.
function finalround.firstWhen(rows: { ledger.Row }, kind: Kind): string?
	local best: string? = nil
	for _, r in rows do
		if r.phase == PHASE[kind] and (best == nil or r.when < best) then
			best = r.when
		end
	end
	return best
end

-- The spend rows of several item folders (spend.md and spend.d, read by `read`), or nil and why one does not read: a
-- file that can't be parsed is a refusal of its own, never "no rows".
function finalround.rowsOf(dirs: { string }, read: (string) -> { ledger.Row }): ({ ledger.Row }?, string?)
	local out: { ledger.Row } = {}
	for _, dir in dirs do
		local ok, rows = pcall(read, dir)
		if not ok then
			return nil,
				`the spend rows of {dir} do not parse ({rows}): the last review round cannot be checked`
		end
		for _, r in rows :: { ledger.Row } do
			table.insert(out, r)
		end
	end
	return out, nil
end

-- The refusal, or nil. `owner` is the item's or raft's id; `requireRound` is true for an issue (an issue that has no
-- design review round at all is refused too: a rafted-in raft with no coherence review is another rule's business). When
-- several rows record the round (a retry), one on a final-review model is enough.
function finalround.check(
	kind: Kind,
	files: { string },
	rows: { ledger.Row },
	enforced: boolean,
	owner: string,
	requireRound: boolean
): string?
	if not enforced then
		return nil
	end
	local n, stem = finalround.lastRound(files, kind)
	if n == nil or stem == nil then
		if requireRound then
			return `{owner} has no {kind} review round: run the adversarial review (./zn dispatch zz-review {owner} --mode {if kind
					== "design"
				then "design"
				else "final"}) and record its model before this step`
		end
		return nil
	end
	local last: ledger.Row? = nil
	for _, r in rows do
		if isRoundRow(r, kind, stem, owner) then
			last = r
			if r.model ~= nil and models.isFinalModel(r.model) then
				return nil
			end
		end
	end
	local what = "there is no row"
	if last ~= nil then
		what = if last.model ~= nil then "model " .. last.model else "no model"
	end
	local mode = if kind == "final"
		then "final"
		elseif string.sub(owner, 1, 1) == "R" then "raft"
		else "design"
	local record = if kind == "design"
		then "./zn spend " .. owner .. " --phase design-review --model <its model id> --note " .. stem
		else './zn commit -m "' .. owner .. ": " .. stem .. '" --phase code-review --model <its model id>'
	return "the last "
		.. kind
		.. " review round ("
		.. stem
		.. ") was not recorded on a final-review model: its spend row has "
		.. what
		.. "; a final round runs a model of a final-review kind (any Opus, kimi k3.1-pro or k3-256k at high or max (the agent CLI's kimi-k3-high and kimi-k3-max stand in), any grok model at xhigh; "
		.. ".models.toml names them for zz-review in order of preference). Run it with ./zn dispatch zz-review "
		.. owner
		.. " --mode "
		.. mode
		.. " (if the review was dispatched, ./zn sync first: its row arrives with origin/main; an interactive reviewer's row: "
		.. record
		.. "; its model is the lead's report), then try again"
end

return finalround
