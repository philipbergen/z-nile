--!strict
-- f0421: the round rule. A review has rounds. The latest round counts; earlier rounds are history. A review file with
-- no verdict and no findings, or a changes verdict and no findings, is malformed. Approve settles the review. A round
-- that is not approve and not responded (a line in the refute file for every finding) waits for the author. A responded
-- round with a high, medium or untagged finding below the maximum is followed by the next round, with no rulings: the
-- next round's reviewer accepts or re-raises each refutation. A responded round with only low findings, or at the
-- maximum, settles once it is also answered (what is refuted or still open is listed under `## Open to the human`,
-- ruled or recorded as a guess), and otherwise waits for that. A maximum is not a minimum. Pure: texts in, a step out.
-- The limits are read by models.rounds.
local openlist = require("./openlist")

local rounds = {}

export type Level = "easy" | "normal" | "risky"
export type Stage = "idea" | "design" | "code"
export type Limits = { idea: number, design: { [string]: number }, code: { [string]: number } }
export type Round = {
	number: number,
	file: string, -- the review file's name
	verdict: string?,
	responded: boolean, -- every finding has a line in the refute file
	answered: boolean, -- and what is refuted or open is ruled (openlist.unanswered): the round is closed
	serious: boolean, -- a high, medium or untagged finding
	seriousCount: number,
	malformed: string?, -- why the file is no review
	open: string?, -- why it is not answered
}
-- `reason` is the sentence for a malformed or rule step; `atMaximum` is the number of serious findings of a review that
-- settled only because it was the last round the maximum allows.
export type Step = {
	kind: "file" | "answer" | "settled" | "malformed" | "rule",
	number: number,
	max: number,
	reason: string?,
	atMaximum: number?,
}

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

-- The level of an item from its members' `risk:` values, in order; nil is a member whose document could not be read.
-- The highest readable level wins, and an unreadable member makes the level at least normal, so a missing member can
-- never lower the maximum below normal. A bad value is a problem naming it.
function rounds.forMembers(risks: { string? }, unreadable: number): (Level?, string?)
	local levels: { Level } = {}
	if unreadable > 0 then
		table.insert(levels, "normal")
	end
	for _, risk in risks do
		local lvl, problem = rounds.level(risk)
		if not lvl then
			return nil, problem
		end
		table.insert(levels, lvl)
	end
	return rounds.highest(levels), nil
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
	local stray: string? = nil
	for name in files do
		if string.sub(name, 1, #reviewPrefix) == reviewPrefix then
			-- exactly three digits: the open list qualifies a bullet by this name, so another spelling is no round
			local digits = string.match(string.sub(name, #reviewPrefix + 1), "^(%d%d%d)%.md$")
			local n = if digits then tonumber(digits) else nil
			if n and n > best then
				best = n
				bestName = name
			elseif not n and string.match(string.sub(name, #reviewPrefix + 1), "^%d+%.md$") then
				stray = name
			end
		end
	end
	if best == 0 then
		if stray then
			return {
				number = 0,
				file = stray,
				verdict = nil,
				responded = false,
				answered = false,
				serious = false,
				seriousCount = 0,
				malformed = `{stray} is not named {reviewPrefix}NNN.md with three digits, so it is no review round: rename it or redo the round`,
			}
		end
		return nil
	end
	local review = files[bestName]
	local num = string.format("%03d", best)
	local refuteName = `{refutePrefix}{num}.md`
	local verdict = rounds.verdict(review)
	local seriousCount = 0
	local findingCount = 0
	for _, f in openlist.findings(review) do
		findingCount += 1
		if f.severity ~= "low" then
			seriousCount += 1
		end
	end
	local malformed: string? = nil
	if findingCount == 0 and #openlist.judgedFails(review) == 0 and verdict ~= "approve" then
		malformed = if verdict == nil
			then `{bestName} has no Verdict line and no findings: fix the file or redo the round`
			else `{bestName} has a {verdict} verdict and no findings: fix the file or redo the round`
	end
	local judged: openlist.Judged = {
		review = review,
		refute = files[refuteName] or "",
		doc = doc,
		reviewName = bestName,
		refuteName = refuteName,
		isBacklog = isBacklog,
	}
	local open = openlist.unanswered(judged)
	return {
		number = best,
		file = bestName,
		verdict = verdict,
		responded = openlist.unresponded(judged) == nil,
		answered = open == nil,
		serious = seriousCount > 0,
		seriousCount = seriousCount,
		malformed = malformed,
		open = open,
	}
end

-- The rule a reviewer of round `n` > 1 follows (F6), naming the previous round's files.
function rounds.laterRule(prevReview: string, prevRefute: string): string
	return `Round 1 reviewed everything: this round only checks the answers. Read {prevReview} and {prevRefute}; check that each fix is real and broke nothing in the lines it touched, accept or re-raise each refutation, and raise a new finding only for a defect in those changes or one round 1 could not have seen.`
end

-- What the loop does next.
function rounds.next(latest: Round?, max: number): Step
	if latest == nil then
		return { kind = "file", number = 1, max = max }
	end
	local n = latest.number
	if latest.malformed ~= nil then
		return { kind = "malformed", number = n, max = max, reason = latest.malformed }
	end
	if latest.verdict == "approve" then
		return { kind = "settled", number = n, max = max }
	end
	if not latest.responded then
		return { kind = "answer", number = n, max = max }
	end
	if latest.serious and n < max then
		return { kind = "file", number = n + 1, max = max }
	end
	if not latest.answered then
		return {
			kind = "rule",
			number = n,
			max = max,
			reason = `{latest.file}: list what is refuted or still open under ## Open to the human, with the qualified id, and have it ruled or recorded as a guess ({latest.open or "open"})`,
		}
	end
	return {
		kind = "settled",
		number = n,
		max = max,
		atMaximum = if latest.serious then latest.seriousCount else nil,
	}
end

return rounds
