--!strict
-- c0248 AC1 to AC3: when a layer is complete. Pure texts through completion.layer and completion.reviewProblem;
-- the one exception reads engine/main.luau as text to prove the final review's rules were moved, not copied.
local completion = require("@znile/engine/completion")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local FINISH = "a2f3c1d9e8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3"
local OLDER = "9b8e7f0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f60"

local function review(commit: string?, verdict: string?, findings: { string }?): string
	local lines = { "# Review 001", "" }
	if commit then
		table.insert(lines, `Commit: {commit}`)
	end
	if verdict then
		table.insert(lines, `Verdict: {verdict}`)
	end
	table.insert(lines, "")
	local listed: { string } = findings or {}
	for _, f in listed do
		table.insert(lines, f)
		table.insert(lines, "The text of the finding.")
		table.insert(lines, "")
	end
	return table.concat(lines, "\n")
end

local function refute(commit: string?, answers: { string }): string
	local lines = { "# Refute 001", "" }
	if commit then
		table.insert(lines, `Commit: {commit}`)
		table.insert(lines, "")
	end
	for _, a in answers do
		table.insert(lines, a)
	end
	return table.concat(lines, "\n") .. "\n"
end

local function has(s: string?, part: string): boolean
	return s ~= nil and string.find(s, part, 1, true) ~= nil
end

local function layer(r: string?, a: string?, doc: string?): string?
	return completion.layer({
		finishSha = FINISH,
		review = r,
		refute = a,
		openList = doc,
		backlog = function(id: string): boolean
			return id == "c0099"
		end,
	})
end

return t.spec("c0248 when a layer is complete", function(it)
	it("AC1: a layer with no review is not complete", function()
		local why = layer(nil, nil, nil)
		t.expect(why ~= nil).toBe(true)
		t.expect(has(why, "review")).toBe(true)
		-- a refute alone is no review
		t.expect(layer(nil, refute(FINISH, { "- F1: fixed abc1234; consequences: none" }), nil) ~= nil).toBe(true)
	end)

	it("AC2: a review with no Verdict line is not complete", function()
		local why = layer(review(FINISH, nil, nil), nil, nil)
		t.expect(why ~= nil).toBe(true)
		t.expect(has(why, "Verdict")).toBe(true)
		-- a verdict word written in prose is no Verdict line
		local prose = "# Review 001\n\nCommit: " .. FINISH .. "\n\nI would approve this.\n"
		t.expect(layer(prose, nil, nil) ~= nil).toBe(true)
	end)

	it(
		"AC2: an unanswered finding, a fixed answer without consequences, a deferred high, an unruled refuted high are each not complete",
		function()
			local medium = review(FINISH, "changes", { "### F1 [medium] a thing" })
			local high = review(FINISH, "changes", { "### F1 [high] a worse thing" })
			-- unanswered
			local unanswered = layer(medium, nil, nil)
			t.expect(unanswered ~= nil).toBe(true)
			t.expect(has(unanswered, "F1")).toBe(true)
			t.expect(layer(medium, refute(FINISH, {}), nil) ~= nil).toBe(true)
			-- fixed without consequences
			local bare = layer(medium, refute(FINISH, { "- F1: fixed abc1234: renamed it" }), nil)
			t.expect(bare ~= nil).toBe(true)
			t.expect(has(bare, "consequences")).toBe(true)
			-- a deferred high is never allowed
			local deferredHigh = layer(high, refute(FINISH, { "- F1: deferred c0099: later" }), nil)
			t.expect(deferredHigh ~= nil).toBe(true)
			t.expect(has(deferredHigh, "high")).toBe(true)
			-- a refuted high waits for the human: not complete until `## Open to the human` rules on it
			local refutedHigh = refute(FINISH, { "- F1: refuted: the reviewer misread it" })
			local open = layer(high, refutedHigh, "# c0010\n\n## Design\nx\n")
			t.expect(open ~= nil).toBe(true)
			t.expect(has(open, "Open to the human")).toBe(true)
			local unruled = "# c0010\n\n## Open to the human\n- F1: the reviewer's finding was refuted\n"
			t.expect(layer(high, refutedHigh, unruled) ~= nil).toBe(true)
			-- and the positives that each rule leaves open
			local ruled = unruled .. "  Ruled (user, 2026-11-12): the refutation stands\n"
			t.expect(layer(high, refutedHigh, ruled)).toBe(nil)
			t.expect(layer(medium, refute(FINISH, { "- F1: fixed abc1234; consequences: none" }), nil)).toBe(nil)
			t.expect(layer(medium, refute(FINISH, { "- F1: deferred c0099: later" }), nil)).toBe(nil)
			-- a deferred finding must name a backlog issue
			t.expect(layer(medium, refute(FINISH, { "- F1: deferred c0098: later" }), nil) ~= nil).toBe(true)
		end
	)

	it("AC3: an approve with no findings naming the finish commit is complete; naming another commit is not", function()
		t.expect(layer(review(FINISH, "approve", nil), nil, nil)).toBe(nil)
		-- a short sha of seven digits or more names the same commit
		t.expect(layer(review(string.sub(FINISH, 1, 7), "approve", nil), nil, nil)).toBe(nil)
		local stale = layer(review(OLDER, "approve", nil), nil, nil)
		t.expect(stale ~= nil).toBe(true)
		-- the reason names both commits and what to do
		t.expect(has(stale, string.sub(OLDER, 1, 7))).toBe(true)
		t.expect(has(stale, string.sub(FINISH, 1, 7))).toBe(true)
		t.expect(has(stale, "Commit:")).toBe(true)
		-- six digits are too short to name a commit
		t.expect(layer(review(string.sub(FINISH, 1, 6), "approve", nil), nil, nil) ~= nil).toBe(true)
	end)

	it(
		"AC3: answered findings whose refute names the finish commit are complete; a refute naming an older commit is not",
		function()
			local changes = review(OLDER, "changes", { "### F1 [medium] a thing", "### F2 [low] another" })
			local answers = { "- F1: fixed abc1234; consequences: none", "- F2: deferred c0099: a later issue" }
			-- the review named the commit it reviewed; the fixes produced a new finish commit that the refute names
			t.expect(layer(changes, refute(FINISH, answers), nil)).toBe(nil)
			local older = layer(changes, refute(OLDER, answers), nil)
			t.expect(older ~= nil).toBe(true)
			t.expect(has(older, string.sub(FINISH, 1, 7))).toBe(true)
			-- no Commit in the refute leaves the review's own Commit, which is older
			t.expect(layer(changes, refute(nil, answers), nil) ~= nil).toBe(true)
			-- a review of the current commit needs no Commit line in its refute
			local current = review(FINISH, "changes", { "### F1 [medium] a thing" })
			t.expect(layer(current, refute(nil, { "- F1: fixed abc1234; consequences: none" }), nil)).toBe(nil)
		end
	)

	it("AC3: a missing Commit line is not complete", function()
		local why = layer(review(nil, "approve", nil), nil, nil)
		t.expect(why ~= nil).toBe(true)
		t.expect(has(why, "Commit")).toBe(true)
		-- not even a refute that names the finish commit stands in for the review's own Commit line
		local changes = review(nil, "changes", { "### F1 [medium] a thing" })
		t.expect(layer(changes, refute(FINISH, { "- F1: fixed abc1234; consequences: none" }), nil) ~= nil).toBe(true)
		-- a Commit line far down the file is not a header
		local late = "# Review 001\n"
			.. string.rep("\nsome text", 30)
			.. "\n\nCommit: "
			.. FINISH
			.. "\nVerdict: approve\n"
		t.expect(layer(late, nil, nil) ~= nil).toBe(true)
		-- an empty finish commit fails closed
		t.expect(completion.layer({ finishSha = "", review = review(FINISH, "approve", nil) }) ~= nil).toBe(true)
	end)

	it("AC2: the final review rules are the same function (moved, not copied)", function()
		-- the same texts, judged as a final review and as a layer review, give the same answer
		local medium = review(FINISH, "changes", { "### F1 [medium] a thing" })
		local cases: { { r: string, a: string? } } = {
			{ r = medium, a = nil },
			{ r = medium, a = refute(nil, { "- F1: fixed abc1234: no consequences" }) },
			{ r = medium, a = refute(nil, { "- F1: fixed abc1234; consequences: none" }) },
			{ r = review(FINISH, "approve", nil), a = nil },
			{
				r = review(FINISH, "changes", { "### F1 [high] bad" }),
				a = refute(nil, { "- F1: deferred c0099: x" }),
			},
		}
		local opts = {
			kind = "layer" :: "layer",
			backlog = function(id: string): boolean
				return id == "c0099"
			end,
		}
		for _, c in cases do
			local direct = completion.reviewProblem(c.r, c.a, "", opts)
			local viaLayer = layer(c.r, c.a, "")
			t.expect(viaLayer).toBe(direct)
			local asFinal = completion.reviewProblem(c.r, c.a, "", {
				kind = "final",
				reviewName = "review-NNN.md",
				refuteName = "refute-NNN.md",
				backlog = opts.backlog,
			})
			t.expect(asFinal).toBe(direct)
		end
		-- a final review that does not exist is named as such, and no layer review stands in for it
		local missing = completion.reviewProblem(nil, nil, "", { kind = "final" })
		t.expect(has(missing, "final-review-NNN.md")).toBe(true)
		-- the rule body is in completion.luau and not in main.luau
		local main = fs.readFile(`{root}/z-nile/engine/main.luau`)
		local module = fs.readFile(`{root}/z-nile/engine/completion.luau`)
		t.expect(has(module, "a fixed answer needs")).toBe(true)
		t.expect(has(main, "a fixed answer needs")).toBe(false)
		t.expect(has(main, "only a medium or low finding can be deferred")).toBe(false)
		t.expect(has(main, "completion.reviewProblem(")).toBe(true)
		t.expect(has(main, "local function reviewProblem(raft: store.Item)")).toBe(true) -- the edge that reads the files
	end)
end)
