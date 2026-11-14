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

-- A header field a review or refute carries on one of its first 12 lines (`Commit: <sha>`, `Patch: <id>`), or nil.
local function stampOf(text: string?, field: string): string?
	if text == nil then
		return nil
	end
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		if n > 12 then
			break
		end
		local value = string.match(line, `^{field}:%s*(%x+)%s*$`)
		if value then
			return string.lower(value)
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

-- Prepends `Commit:` and `Patch:` to a review or refute that lacks them (the tool stamps; the reviewer never writes
-- them). A text that already carries a line keeps it. The lines go after the first heading line, if there is one.
function completion.stamp(text: string, sha: string, patch: string): string
	local have = {
		Commit = stampOf(text, "Commit") ~= nil,
		Patch = stampOf(text, "Patch") ~= nil,
	}
	local add: { string } = {}
	if not have.Commit then
		table.insert(add, `Commit: {sha}`)
	end
	if not have.Patch then
		table.insert(add, `Patch: {patch}`)
	end
	if #add == 0 then
		return text
	end
	local head, rest = string.match(text, "^(#[^\n]*\n)(.*)$")
	if head then
		return head .. "\n" .. table.concat(add, "\n") .. "\n" .. (string.gsub(rest :: string, "^\n", "", 1))
	end
	return table.concat(add, "\n") .. "\n\n" .. text
end

local function findingCountOf(review: string): number
	local n = 0
	for _ in string.gmatch("\n" .. review, "\n###%s+F%d+") do
		n += 1
	end
	return n
end

local function fixedAnswers(refute: string?): number
	local n = 0
	for _ in string.gmatch("\n" .. (refute or ""), "\n%-%s+F%d+:%s*fixed") do
		n += 1
	end
	return n
end

local function names(stamp: string?, patch: string?, sha: string, pid: string): boolean
	return (stamp ~= nil and sameCommit(stamp, sha)) or (patch ~= nil and patch == string.lower(pid))
end

-- nil when the layer is complete: its newest review has a Verdict and a stamp, every finding is answered by the final
-- review's rules, and the review is current: its `Commit:` is the finish commit, or its `Patch:` the finish commit's
-- patch id (a clean rebase keeps the patch); or, when it has findings and its refute answers at least one `fixed`, the
-- refute's `Commit:` or `Patch:` matches. A refute never carries an approve with no findings, or answers that are
-- all refuted or deferred, to a changed patch. Anything else, an unreadable file included, is a reason (fail closed).
function completion.layer(input: {
	finishSha: string,
	patchId: string,
	review: string?,
	refute: string?,
	doc: string?,
	backlog: ((string) -> boolean)?,
	reviewName: string?,
	refuteName: string?,
}): string?
	local reviewName = input.reviewName or "review-NNN.md"
	local refuteName = input.refuteName or "refute-NNN.md"
	if input.finishSha == "" or input.patchId == "" then
		return "the layer has no finish commit"
	end
	if input.review == nil then
		return "no review-NNN.md in the issue's folder: review this layer"
	end
	if string.match("\n" .. input.review, "\n[Vv]erdict:%s*%a+") == nil then
		return `{reviewName} has no Verdict: line`
	end
	local reviewedSha = stampOf(input.review, "Commit")
	local reviewedPatch = stampOf(input.review, "Patch")
	if reviewedSha == nil and reviewedPatch == nil then
		return `{reviewName} has no Commit: line (the tool stamps Commit: and Patch: when ./zn commit commits it)`
	end
	local problem = completion.reviewProblem(input.review, input.refute, input.doc, {
		kind = "layer",
		reviewName = reviewName,
		refuteName = refuteName,
		backlog = input.backlog,
	})
	if problem then
		return problem
	end
	if names(reviewedSha, reviewedPatch, input.finishSha, input.patchId) then
		return nil
	end
	local short = string.sub(input.finishSha, 1, 7)
	if
		findingCountOf(input.review) > 0
		and fixedAnswers(input.refute) > 0
		and names(
			stampOf(input.refute, "Commit"),
			stampOf(input.refute, "Patch"),
			input.finishSha,
			input.patchId
		)
	then
		return nil
	end
	local seen = if reviewedSha then string.sub(reviewedSha, 1, 7) else "?"
	local seenPatch = if reviewedPatch then string.sub(reviewedPatch, 1, 4) else "?"
	return `{reviewName} reviewed {seen} (patch {seenPatch}...), the layer is at {short} (patch {string.sub(
		input.patchId,
		1,
		4
	)}...): the change differs, so answer it in {refuteName} with a fixed finding or review again`
end

return completion
