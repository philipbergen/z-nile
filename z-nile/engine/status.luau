--!strict
-- Item status: pure rules, no I/O. See c0510.
local status = {}

-- `done` is never set by hand: an item is done when it sits in done/ (tracker.sh done moves it).
-- `closed` (won't do, c0278) is set only by `./zn close`, and nothing leaves it: no move here enters or leaves it.
local ALLOWED: { [string]: boolean } = {
	["new>preparing"] = true,
	["preparing>prepared"] = true,
	["preparing>new"] = true,
	["prepared>active"] = true,
	["prepared>preparing"] = true,
	["active>prepared"] = true,
}
local NAMES: { [string]: boolean } =
	{ new = true, preparing = true, prepared = true, active = true, done = true, closed = true }
local WORDS = {
	"raging",
	"pink",
	"mongoose",
	"quiet",
	"copper",
	"falcon",
	"brisk",
	"amber",
	"otter",
	"lucky",
	"violet",
	"heron",
	"mellow",
	"crimson",
	"badger",
	"jolly",
	"silver",
	"walrus",
	"plucky",
	"indigo",
	"lynx",
	"sunny",
	"marble",
	"toucan",
}

function status.canMove(from: string, to: string): boolean
	return ALLOWED[`{from}>{to}`] == true
end

-- Only a finished review lands the content itself, so only this move rides the PR.
function status.carriedByPr(from: string, to: string): boolean
	return from == "preparing" and to == "prepared"
end

-- A fresh `<state>-<three words>` value. Two terminals making the same move write different lines,
-- so git reports a conflict instead of merging them silently. `pick(n)` returns 1..n.
function status.stamp(state: string, pick: (number) -> number): string
	return `{state}-{WORDS[pick(#WORDS)]}-{WORDS[pick(#WORDS)]}-{WORDS[pick(#WORDS)]}`
end

-- A stamp from `draw` that `taken` rejects for no value, redrawn up to `tries` times (default 50); nil when every
-- draw was taken. A claim stamp names the raft's claimed set, so it must be new on origin/main (R0025 review 004 F1).
function status.fresh(draw: () -> string, taken: (string) -> boolean, tries: number?): string?
	for _ = 1, tries or 50 do
		local value = draw()
		if not taken(value) then
			return value
		end
	end
	return nil
end

-- The state of a stored value: `active` or `active-quiet-copper-falcon`; nil for anything else.
function status.parse(value: string?): string?
	if not value then
		return nil
	end
	local plain = string.match(value, "^(%a+)$") or string.match(value, "^(%a+)%-%a+%-%a+%-%a+$")
	if plain and NAMES[plain] then
		return plain
	end
	return nil
end

-- The three words of a stamped value, or nil for a plain one.
function status.phrase(value: string?): string?
	return if value then string.match(value, "^%a+%-(%a+%-%a+%-%a+)$") else nil
end

-- `inRaft`: the item names a raft (an issue with `raft:`) or is a raft itself: a draft one is being prepared.
function status.derive(state: string, design: string?, inRaft: boolean?): string
	if state ~= "backlog" then
		return state
	end
	if design == "ready" then
		return "prepared"
	end
	return if inRaft then "preparing" else "new"
end

-- An existing draft raft is `preparing` only by derivation (nothing stored), so it is claimed by
-- stamping it once. The claim applies to a raft and, through it, its members; `viaRaft` is false for
-- an issue named on its own, which can never be claimed that way.
function status.canClaim(from: string, to: string, stored: boolean, viaRaft: boolean): boolean
	return from == "preparing" and to == "preparing" and not stored and viaRaft
end

function status.effective(front: { [string]: string }, state: string): string
	if state == "done" then
		return "done"
	end
	local inRaft = (front.raft or "") ~= "" or front.issues ~= nil
	return status.parse(front.status) or status.derive(state, front.design, inRaft)
end

-- c0161: the lines of a design review round that the engine reads, from one reader (the move to prepared, the check at
-- the next read, and the re-record after an id rewrite all use it). A round is written once, so a second `Verdict: ` line
-- or a second `Design record: ` line (each at the start of a line) is a problem, and so is a `Design record:` line that
-- is not just a hash. Returns the last verdict word (trailing spaces dropped), the quoted hash, and the problem, if any.
function status.roundLines(text: string): (string?, string?, string?)
	local verdict, record, problem = nil, nil, nil
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if string.sub(line, 1, #"Verdict: ") == "Verdict: " then
			if verdict ~= nil then
				problem = 'has two "Verdict:" lines: a round is written once (zz-review)'
			end
			verdict = (string.gsub(string.sub(line, #"Verdict: " + 1), "%s+$", ""))
		elseif string.sub(line, 1, #"Design record:") == "Design record:" then
			local hash = string.match(line, "^Design record: (%x+)[ \r]*$")
			if hash == nil then
				problem = 'has a "Design record:" line that is not just the hash (zz-review)'
			elseif record ~= nil then
				problem = 'has two "Design record:" lines: a round is written once (zz-review)'
			end
			record = hash or record
		end
	end
	return verdict, record, problem
end

-- The same round with its quoted record `from` replaced by `to` (only on a line that is exactly the quote).
function status.rewriteRecord(text: string, from: string, to: string): string
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if string.match(line, "^Design record: (%x+)[ \r]*$") == from then
			table.insert(out, (string.gsub(line, from, to, 1)))
		else
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n")
end

-- The highest round number in a folder's files (0: none): `design-review-NNN.md`, three digits, top level only (the
-- pattern is `lessons.isStem`'s).
local function newestRound(files: { [string]: string }): number
	local newest = 0
	for rel in files do
		local n = string.match(rel, "^design%-review%-(%d%d%d)%.md$")
		if n and (tonumber(n) :: number) > newest then
			newest = tonumber(n) :: number
		end
	end
	return newest
end

-- c0161: whether an issue's folder holds the design review z-design step 5 requires before the move to `prepared`.
-- `files`: the folder's files, path relative to it -> text; `record`: the design as it is now (`raftplan.designRecord`).
-- nil when the newest round approves and quotes the design as it is; else the problem, which starts with the file it is
-- about. The newest `design-review-NNN.md` decides, and only a reviewer's word counts: its `Verdict:` is `approve`, and
-- its `Design record: <hash>` equals `record`. A round that says `changes` is never the last (answering its findings by
-- an edit needs a new round), and a Design changed after the approving round needs a new one: refutes, harvest and
-- spend are not read. The engine cannot tell what a review judged, only that a reviewer's round of this design
-- approved it. `done` reads code-review files (`review-NNN.md`, `refute-NNN.md`) with its own rules; the finding
-- convention elsewhere is `lessons.findings`'.
function status.designReviewProblem(files: { [string]: string }, record: string): string?
	local newest = newestRound(files)
	if newest == 0 then
		return "has no design-review-001.md: z-design step 5 runs at least one clean review round on every issue before `prepared`, a closure (no code change) included"
	end
	local name = `design-review-{string.format("%03d", newest)}.md`
	local verdict, quoted, problem = status.roundLines(files[name])
	if problem then
		return `{name} {problem}`
	end
	if verdict == "changes" then
		return `{name} says "Verdict: changes": the final round approves, so answer it by editing the design and running the next round (z-design step 5.4); a refute alone does not stand in for it`
	end
	if verdict ~= "approve" then
		return `{name} has no "Verdict: approve" or "Verdict: changes" line (zz-review's format)`
	end
	if quoted == nil then
		return `{name} quotes no "Design record: <hash>" line: the reviewer ends the round with the output of ./zn design-record <id>`
	end
	if quoted ~= record then
		return `{name} quotes Design record {quoted}, but the design is now {record}: it changed after this round, or the round quoted another checkout's design; make it current with a design round for this issue, run in the worktree that holds the edit and landed with it (z-design 5.3: a Design changed after a round, or by answering one, needs a new round; for a rafted member: unfold it with the edit and the round, land, then fold it again: z-raft 2)`
	end
	return nil
end

-- c0161, "Check at next read": whether a prepared issue, as it is on origin/main, still matches the record its newest
-- round quotes. An issue none of whose rounds quotes a record was prepared by an engine that predates the rule and is
-- exempt (nil): the exempt set is found by search, never listed by hand. Read by `new raft`, `fold`, `recombine` and
-- `ready`, so a design edited after the move to prepared (a gate fix, a PR answer, a conflict resolved in the document)
-- is caught before the issue is rafted or readied.
function status.preparedReadProblem(files: { [string]: string }, record: string): string?
	local quotes = false
	for rel, text in files do
		if string.match(rel, "^design%-review%-%d%d%d%.md$") then
			local _, quoted = status.roundLines(text)
			if quoted ~= nil then
				quotes = true
			end
		end
	end
	if not quotes then
		return nil
	end
	local problem = status.designReviewProblem(files, record)
	if problem then
		return `is prepared on origin/main but {problem}`
	end
	return nil
end

function status.nextNumber(ids: { string }): number
	local max = 0
	for _, id in ids do
		max = math.max(max, tonumber(string.sub(id, 2)) or 0)
	end
	return (math.floor(max / 10) + 1) * 10
end

return status
