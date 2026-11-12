--!strict
-- When a review settles a piece of work. Pure: texts in, a reason out (nil when settled). Reads stay in main.luau
-- and layergit.luau. One rule for the final review at `done` and for a layer's review at `start` and `done`
-- (zz-arch: one reader per format); c0262 adds its full-force input to `completion.layer`.
local openlist = require("./openlist")

local completion = {}

export type Opts = {
	kind: "final" | "layer",
	-- the file names the reasons quote; the defaults are the numbered names a caller has not resolved
	reviewName: string?,
	refuteName: string?,
	-- true when `id` is a backlog issue (a deferred finding must name one); nil is "none is", fail closed
	backlog: ((string) -> boolean)?,
}

-- Review answered once: verdict approve, or every finding answered ("fixed ...; consequences: ...", "refuted", or a
-- valid "deferred <id>: <why>"), or ruled by the human under `## Open to the human` in `openList` (a document's text).
-- Moved, not copied, from main.luau's reviewProblem; the final review reads the raft's document, a layer's its issue's.
function completion.reviewProblem(review: string?, refute: string?, openList: string?, opts: Opts): string?
	local reviewName = opts.reviewName
		or (if opts.kind == "final" then "final-review-NNN.md" else "review-NNN.md")
	local refuteName = opts.refuteName
		or (if opts.kind == "final" then "final-refute-NNN.md" else "refute-NNN.md")
	if review == nil then
		if opts.kind == "final" then
			return "no final-review-NNN.md (no review-NNN.md may stand in for the final review): run the final review first"
		end
		return "no review-NNN.md in the issue's folder: review this layer"
	end
	local body = "\n" .. review
	local verdict = string.match(body, "\n[Vv]erdict:%s*(%a+)")
	if verdict == "approve" then
		return nil
	end
	local doc = openList or ""
	local humanSection = string.match("\n" .. doc, "\n## Open to the human\n(.-)\n## ")
		or string.match("\n" .. doc, "\n## Open to the human\n(.*)$")
		or ""
	local inHuman: { [string]: boolean } = {}
	for fid in string.gmatch("\n" .. humanSection, "\n%- (F%d+):") do
		inHuman[fid] = true
	end
	local pendingSet: { [string]: boolean } = {}
	for _, fid in openlist.pending(doc) do
		pendingSet[fid] = true
	end

	local answers = "\n" .. (refute or "")
	local missing = {}
	local invalid = {}
	local findingCount = 0
	for id, rest in string.gmatch(body, "\n###%s+(F%d+)([^\n]*)") do
		findingCount += 1
		local line = string.match(answers, `\n%-%s+{id}:%s*([^\n]*)`)
		if line and string.find(line, "^fixed") then
			if not string.find(line, "consequences:%s*%S", 6) then
				table.insert(
					invalid,
					`{id}: a fixed answer needs "; consequences: <what the fix could break, and how that was checked, or none>"`
				)
			end
			continue
		end
		if line and string.find(line, "^refuted") then
			continue
		end
		if inHuman[id] and not pendingSet[id] then
			continue
		end
		if not line or not (line == "deferred" or string.find(line, "^deferred%s")) then
			if inHuman[id] and pendingSet[id] then
				continue
			end
			table.insert(missing, id)
			continue
		end
		local target = string.match(line, "^deferred%s+([fdc]%d%d%d%d):%s*%S")
		local severity = string.match(rest or "", "^%s*%[(%a+)%]")
		local rating = if severity then string.lower(severity) else "unrated"
		if not target then
			table.insert(invalid, `{id}: deferred needs "<issue id>: <why>"`)
		elseif rating ~= "medium" and rating ~= "low" then
			table.insert(invalid, `{id} is {rating}: only a medium or low finding can be deferred`)
		elseif not (opts.backlog ~= nil and opts.backlog(target)) then
			table.insert(invalid, `{id}: {target} is not a backlog issue`)
		end
	end
	if #missing > 0 then
		return `{reviewName} findings not answered in {refuteName}: {table.concat(missing, ", ")}`
	end
	if #invalid > 0 then
		return `{refuteName}: {table.concat(invalid, "; ")}`
	end
	-- one round: a refuted finding, an unclosed high, or a failed Judged criterion waits for the human
	local gap = openlist.problem(body, answers, doc)
	if gap then
		return `{reviewName} {gap}`
	end
	if verdict ~= nil and findingCount == 0 and #openlist.judgedFails(body) == 0 then
		return `{reviewName} Verdict is {verdict}, not approve`
	end
	return nil
end

-- The sha a review file names on one of its first lines (`Commit: <sha>`), or nil.
local function commitOf(text: string?): string?
	if text == nil then
		return nil
	end
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		if n > 12 then
			break
		end
		local sha = string.match(line, "^Commit:%s*(%x+)%s*$")
		if sha then
			return string.lower(sha)
		end
	end
	return nil
end

-- Two shas name the same commit when one is a prefix of the other and the shorter has 7 or more digits.
local function sameCommit(a: string, b: string): boolean
	local x, y = string.lower(a), string.lower(b)
	local short = if #x < #y then x else y
	local long = if #x < #y then y else x
	return #short >= 7 and string.sub(long, 1, #short) == short
end

-- nil when the layer is complete: its newest review has a Verdict, every finding is answered by the final review's
-- rules, and the review is current (its `Commit:`, or its refute's, is the layer's finish commit). Anything else,
-- an unreadable file included, is a reason (fail closed).
function completion.layer(input: {
	finishSha: string,
	review: string?,
	refute: string?,
	openList: string?,
	backlog: ((string) -> boolean)?,
	reviewName: string?,
	refuteName: string?,
}): string?
	local reviewName = input.reviewName or "review-NNN.md"
	local refuteName = input.refuteName or "refute-NNN.md"
	if input.finishSha == "" then
		return "the layer has no finish commit"
	end
	if input.review == nil then
		return "no review-NNN.md in the issue's folder: review this layer"
	end
	if string.match("\n" .. input.review, "\n[Vv]erdict:%s*%a+") == nil then
		return `{reviewName} has no Verdict: line`
	end
	local reviewed = commitOf(input.review)
	if reviewed == nil then
		return `{reviewName} has no Commit: line (its first lines carry Commit: <sha>, the finish commit it reviewed)`
	end
	local problem = completion.reviewProblem(input.review, input.refute, input.openList, {
		kind = "layer",
		reviewName = reviewName,
		refuteName = refuteName,
		backlog = input.backlog,
	})
	if problem then
		return problem
	end
	local answered = commitOf(input.refute)
	if
		sameCommit(reviewed, input.finishSha) or (answered ~= nil and sameCommit(answered, input.finishSha))
	then
		return nil
	end
	local short = string.sub(input.finishSha, 1, 7)
	return `{reviewName} names {string.sub(reviewed, 1, 7)}, the layer is at {short} (re-review, or answer it in {refuteName} with Commit: {short})`
end

return completion
