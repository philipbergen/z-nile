--!strict
-- f0421: the round rule. A review has rounds. The latest round counts; earlier rounds are history. Approve settles the
-- review. A round that is not approve and not answered waits for the author. An answered round with a high or medium
-- finding below the maximum is followed by the next round; an answered round with only low findings, or at the
-- maximum, settles. A maximum is not a minimum. Pure: texts in, a step out. The limits are read by models.rounds.
local openlist = require("./openlist")

local rounds = {}

export type Level = "easy" | "normal" | "risky"
export type Stage = "idea" | "design" | "code"
export type Limits = { idea: number, design: { [string]: number }, code: { [string]: number } }
export type Round = { number: number, verdict: string?, answered: boolean, serious: boolean }
export type Step = { kind: "file" | "answer" | "settled", number: number, max: number }

rounds.LEVELS = { "easy", "normal", "risky" } :: { string }
rounds.STAGES = { "idea", "design", "code" } :: { string }

rounds.DEFAULT = {
	idea = 3,
	design = { easy = 2, normal = 5, risky = 9 },
	code = { easy = 2, normal = 5, risky = 9 },
} :: Limits

-- Each kind of review: its review prefix and its refute prefix (matched as plain prefixes).
rounds.KINDS = {
	design = { "design-review-", "design-refute-" },
	code = { "review-", "refute-" },
	final = { "final-review-", "final-refute-" },
} :: { [string]: { string } }

-- A risk value as a level: nil or "" is normal; anything but easy, normal or risky is a problem.
function rounds.level(value: string?): (Level?, string?)
	if value == nil or value == "" then
		return "normal", nil
	end
	if value == "easy" or value == "normal" or value == "risky" then
		return value :: Level, nil
	end
	return nil, `risk is {value}: easy, normal or risky`
end

-- The raft rule: its members' highest level; normal when it has none.
function rounds.highest(levels: { Level }): Level
	if table.find(levels, "risky") then
		return "risky"
	elseif table.find(levels, "normal") then
		return "normal"
	elseif table.find(levels, "easy") then
		return "easy"
	end
	return "normal"
end

-- The most rounds a stage may have at a level (the idea stage has no level).
function rounds.max(l: Limits, stage: Stage, level: string): number
	if stage == "idea" then
		return l.idea
	end
	return l[stage][level]
end

-- The one reader of a review's `Verdict:` line.
function rounds.verdict(text: string): string?
	return string.match("\n" .. text, "\n[Vv]erdict:%s*(%a+)")
end

-- The latest round of one kind of review in `files` (name -> text), or nil when there is none.
function rounds.latest(
	files: { [string]: string },
	kind: string,
	doc: string,
	isBacklog: (string) -> boolean
): Round?
	local prefixes = rounds.KINDS[kind]
	if prefixes == nil then
		return nil
	end
	local reviewPrefix, refutePrefix = prefixes[1], prefixes[2]
	local best, bestName = 0, ""
	for name in files do
		if string.sub(name, 1, #reviewPrefix) == reviewPrefix then
			local digits = string.match(string.sub(name, #reviewPrefix + 1), "^(%d+)%.md$")
			local n = if digits then tonumber(digits) else nil
			if n and n > best then
				best = n
				bestName = name
			end
		end
	end
	if best == 0 then
		return nil
	end
	local review = files[bestName]
	local num = string.format("%03d", best)
	local refuteName = `{refutePrefix}{num}.md`
	local verdict = rounds.verdict(review)
	local serious = false
	for _, f in openlist.findings(review) do
		if f.severity == "high" or f.severity == "medium" then
			serious = true
		end
	end
	local problem = openlist.unanswered({
		review = review,
		refute = files[refuteName] or "",
		doc = doc,
		reviewName = bestName,
		refuteName = refuteName,
		isBacklog = isBacklog,
	})
	return { number = best, verdict = verdict, answered = problem == nil, serious = serious }
end

-- What the loop does next.
function rounds.next(latest: Round?, max: number): Step
	if latest == nil then
		return { kind = "file", number = 1, max = max }
	end
	local n = latest.number
	if latest.verdict == "approve" then
		return { kind = "settled", number = n, max = max }
	end
	if not latest.answered then
		return { kind = "answer", number = n, max = max }
	end
	if latest.serious and n < max then
		return { kind = "file", number = n + 1, max = max }
	end
	return { kind = "settled", number = n, max = max }
end

return rounds
