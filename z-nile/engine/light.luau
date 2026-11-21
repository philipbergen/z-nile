--!strict
-- f0420 step 3: the light path. An easy ticket that is in no raft (or in the single raft `ready <issue>` made for it)
-- goes from designed to done in one pull request, with ONE review: the final review, which also reviews the code.
-- This is the one place that says what "light" means. Pure: facts in, an answer out. Reads are the callers'.
--
-- A ticket is light when ALL of these hold:
--   - it is the only ticket of its raft (a raftless ticket is a raft of one in the making);
--   - its `risk:` is easy (absent means normal, so not light; a bad value is not light);
--   - its design is ready and it has no dependency that has not landed;
--   - its Regression guard has no `Overrides:` entry (a change to a finished ticket's promoted spec needs the separate
--     code review, whatever the risk says);
--   - once built, its own diff changes at most `light.BOUND` lines outside specs and the tracker (the walk then asks
--     for the code review as for any raft, and says why).
-- Risk is set by the author's branch, so the last two are what keep "easy" honest.

local rounds = require("./rounds")

local light = {}

-- Changed lines (added plus removed) outside specs and the tracker above which an easy ticket is no longer light.
-- A guess (f0420 Design, G12): 150 is about a page of engine code, the size of the easy tickets seen so far. Too low
-- sends honest easy tickets to the code review (the cost is the review it would have had anyway); too high lets an
-- easy label cover a large change with one review instead of two.
light.BOUND = 150

export type Member = {
	risk: string?,
	doc: string, -- the ticket's document (for its Regression guard)
	designReady: boolean,
}

export type Facts = {
	members: { Member },
	depsMet: boolean,
	changed: number?, -- lines changed outside specs by the ticket's diff, once it is built. Nil: not built yet.
}

-- Whether the Regression guard of a ticket document has an `Overrides:` entry other than none.
function light.overrides(doc: string): boolean
	local body = string.match("\n" .. doc .. "\n## ", "\n## Regression guard[^\n]*\n(.-)\n## ")
	if not body then
		return false
	end
	for line in string.gmatch(body, "[^\n]+") do
		local entry = string.match(line, "^%s*Overrides:%s*(.-)%s*$")
		if entry then
			local bare = string.lower((string.gsub(entry, "[%s%.`*_]", "")))
			if bare ~= "" and bare ~= "none" and string.sub(bare, 1, 5) ~= "none(" then
				return true
			end
		end
	end
	return false
end

-- A path whose lines do not count toward the bound: a spec, or tracker text.
local function exempt(path: string): boolean
	return string.match(path, "%.spec%.luau$") ~= nil
		or string.match(path, "%.watch%.txt$") ~= nil
		or string.find(path, "/%.tracker/") ~= nil
		or string.match(path, "^%.tracker/") ~= nil
		or string.find(path, "/tests/", 1, true) ~= nil
end

-- The changed lines (added plus removed) of `git diff --numstat` output, outside specs and the tracker. A binary
-- file (`-`) counts as the bound plus one: it is never small.
function light.changedLines(numstat: string): number
	local total = 0
	for line in string.gmatch(numstat, "[^\n]+") do
		local added, removed, path = string.match(line, "^(%S+)\t(%S+)\t(.+)$")
		if added and removed and path and not exempt(path) then
			total += (tonumber(added) or light.BOUND + 1) + (tonumber(removed) or 0)
		end
	end
	return total
end

-- nil when the ticket is light, else the first reason it is not.
function light.reason(f: Facts): string?
	if #f.members ~= 1 then
		return "its raft has more than one ticket"
	end
	local m = f.members[1]
	local level, problem = rounds.level(m.risk)
	if not level then
		return problem :: string
	end
	if level ~= "easy" then
		return `its risk is {level}, not easy`
	end
	if not m.designReady then
		return "its design is not ready"
	end
	if not f.depsMet then
		return "a dependency has not landed"
	end
	if light.overrides(m.doc) then
		return "its Regression guard overrides a finished ticket's promoted acceptance spec (the separate code review covers that)"
	end
	if f.changed ~= nil and (f.changed :: number) > light.BOUND then
		return `its diff changes {f.changed} lines outside specs, over the bound of {light.BOUND}`
	end
	return nil
end

function light.is(f: Facts): boolean
	return light.reason(f) == nil
end

return light
