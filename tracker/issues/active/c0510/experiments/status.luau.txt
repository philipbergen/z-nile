--!strict
-- Item status: pure rules, no I/O. See c0510.
local status = {}

-- `done` is never set by hand: an item is done when it sits in done/ (tracker.sh done moves it).
local ALLOWED: { [string]: boolean } = {
	["new>preparing"] = true,
	["preparing>prepared"] = true,
	["preparing>new"] = true,
	["prepared>active"] = true,
	["prepared>preparing"] = true,
	["active>prepared"] = true,
}
local NAMES: { [string]: boolean } =
	{ new = true, preparing = true, prepared = true, active = true, done = true }
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

function status.nextNumber(ids: { string }): number
	local max = 0
	for _, id in ids do
		max = math.max(max, tonumber(string.sub(id, 2)) or 0)
	end
	return (math.floor(max / 10) + 1) * 10
end

return status
