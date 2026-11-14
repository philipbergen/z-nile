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
local PATCH = "4c1d7e02a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4"
local OTHER_PATCH = "7e02b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4"

-- The stamp lines a review or refute carries on its first lines: `Commit:` and `Patch:`, either of them or neither.
local function review(commit: string?, verdict: string?, findings: { string }?, patch: string?): string
	local lines = { "# Review 001", "" }
	if commit then
		table.insert(lines, `Commit: {commit}`)
	end
	if patch then
		table.insert(lines, `Patch: {patch}`)
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

local function refute(commit: string?, answers: { string }, patch: string?): string
	local lines = { "# Refute 001", "" }
	if commit then
		table.insert(lines, `Commit: {commit}`)
	end
	if patch then
		table.insert(lines, `Patch: {patch}`)
	end
	if commit or patch then
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

-- The layer's current state is its finish commit FINISH and the patch id PATCH, unless a case gives another patch.
local function layer(r: string?, a: string?, doc: string?, patch: string?): string?
	return completion.layer({
		finishSha = FINISH,
		patchId = patch or PATCH,
		review = r,
		refute = a,
		doc = doc,
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
		t.expect(layer(nil, refute(FINISH, { "- F1: fixed abc1234; consequences: none" }, PATCH), nil) ~= nil)
			.toBe(true)
	end)

	it("AC2: a review with no Verdict line is not complete", function()
		local why = layer(review(FINISH, nil, nil, PATCH), nil, nil)
		t.expect(why ~= nil).toBe(true)
		t.expect(has(why, "Verdict")).toBe(true)
		-- a verdict word written in prose is no Verdict line
		local prose = "# Review 001\n\nCommit: " .. FINISH .. "\n\nI would approve this.\n"
		t.expect(layer(prose, nil, nil) ~= nil).toBe(true)
	end)

	it(
		"AC2: an unanswered finding, a fixed answer without consequences, a deferred high, an unruled refuted high are each not complete",
		function()
			local medium = review(FINISH, "changes", { "### F1 [medium] a thing" }, PATCH)
			local high = review(FINISH, "changes", { "### F1 [high] a worse thing" }, PATCH)
			-- unanswered
			local unanswered = layer(medium, nil, nil)
			t.expect(unanswered ~= nil).toBe(true)
			t.expect(has(unanswered, "F1")).toBe(true)
			t.expect(layer(medium, refute(FINISH, {}, PATCH), nil) ~= nil).toBe(true)
			-- fixed without consequences
			local bare = layer(medium, refute(FINISH, { "- F1: fixed abc1234: renamed it" }, PATCH), nil)
			t.expect(bare ~= nil).toBe(true)
			t.expect(has(bare, "consequences")).toBe(true)
			-- a deferred high is never allowed
			local deferredHigh = layer(high, refute(FINISH, { "- F1: deferred c0099: later" }, PATCH), nil)
			t.expect(deferredHigh ~= nil).toBe(true)
			t.expect(has(deferredHigh, "high")).toBe(true)
			-- a refuted high waits for the human: not complete until `## Open to the human` rules on it
			local refutedHigh = refute(FINISH, { "- F1: refuted: the reviewer misread it" }, PATCH)
			local open = layer(high, refutedHigh, "# c0010\n\n## Design\nx\n")
			t.expect(open ~= nil).toBe(true)
			t.expect(has(open, "Open to the human")).toBe(true)
			local unruled = "# c0010\n\n## Open to the human\n- F1: the reviewer's finding was refuted\n"
			t.expect(layer(high, refutedHigh, unruled) ~= nil).toBe(true)
			-- and the positives that each rule leaves open
			t.expect(layer(medium, refute(FINISH, { "- F1: fixed abc1234; consequences: none" }, PATCH), nil))
				.toBe(nil)
			t.expect(layer(medium, refute(FINISH, { "- F1: deferred c0099: later" }, PATCH), nil)).toBe(nil)
			-- a deferred finding must name a backlog issue
			t.expect(layer(medium, refute(FINISH, { "- F1: deferred c0098: later" }, PATCH), nil) ~= nil)
				.toBe(true)
		end
	)

	it(
		"AC2: a refuted high ruled in the issue document is complete; the same ruling only in the raft document is not",
		function()
			local high = review(FINISH, "changes", { "### F1 [high] a worse thing" }, PATCH)
			local refutedHigh = refute(FINISH, { "- F1: refuted: the reviewer misread it" }, PATCH)
			local ruling =
				"## Open to the human\n- F1: the reviewer's finding was refuted\n  Ruled (user, 2026-11-12): the refutation stands\n"
			-- the layer's open list is the issue document's: `doc` is that document
			local issueDoc = "# c0010\n\n## Design\nx\n\n" .. ruling
			t.expect(layer(high, refutedHigh, issueDoc)).toBe(nil)
			-- the same ruling written in the raft document is not the layer's: the issue document has none
			local issueWithout = "# c0010\n\n## Design\nx\n"
			local why = layer(high, refutedHigh, issueWithout)
			t.expect(why ~= nil).toBe(true)
			t.expect(has(why, "Open to the human")).toBe(true)
			-- an unruled bullet stays pending
			local pending = "# c0010\n\n## Open to the human\n- F1: the reviewer's finding was refuted\n"
			t.expect(layer(high, refutedHigh, pending) ~= nil).toBe(true)
		end
	)

	it(
		"AC3: an approve naming the finish commit is complete; naming another commit with another patch is not",
		function()
			t.expect(layer(review(FINISH, "approve", nil, PATCH), nil, nil)).toBe(nil)
			-- the commit alone is a stamp, and a short sha of seven digits or more names the same commit
			t.expect(layer(review(FINISH, "approve", nil), nil, nil)).toBe(nil)
			t.expect(layer(review(string.sub(FINISH, 1, 7), "approve", nil), nil, nil)).toBe(nil)
			local stale = layer(review(OLDER, "approve", nil, OTHER_PATCH), nil, nil)
			t.expect(stale ~= nil).toBe(true)
			-- the reason names both commits and both patches, and what to do
			t.expect(has(stale, string.sub(OLDER, 1, 7))).toBe(true)
			t.expect(has(stale, string.sub(FINISH, 1, 7))).toBe(true)
			t.expect(has(stale, string.sub(OTHER_PATCH, 1, 4))).toBe(true)
			t.expect(has(stale, string.sub(PATCH, 1, 4))).toBe(true)
			t.expect(has(stale, "refute-NNN.md")).toBe(true)
			-- six digits are too short to name a commit
			t.expect(layer(review(string.sub(FINISH, 1, 6), "approve", nil), nil, nil) ~= nil).toBe(true)
		end
	)

	it("AC3: an approve naming another commit with the same patch is complete", function()
		-- a clean rebase keeps the patch and changes the commit
		t.expect(layer(review(OLDER, "approve", nil, PATCH), nil, nil)).toBe(nil)
		-- the patch alone is a stamp
		t.expect(layer(review(nil, "approve", nil, PATCH), nil, nil)).toBe(nil)
		-- a patch that differs by one digit is another patch
		local almost = string.sub(PATCH, 1, #PATCH - 1) .. "5"
		t.expect(layer(review(OLDER, "approve", nil, almost), nil, nil) ~= nil).toBe(true)
	end)

	it("AC3: a refute with a fixed answer stamped with the finish commit carries the review", function()
		local changes =
			review(OLDER, "changes", { "### F1 [medium] a thing", "### F2 [low] another" }, OTHER_PATCH)
		local answers = { "- F1: fixed abc1234; consequences: none", "- F2: deferred c0099: a later issue" }
		-- the review named the commit it reviewed; the fix produced a new finish commit that the refute names
		t.expect(layer(changes, refute(FINISH, answers), nil)).toBe(nil)
		-- or the new patch
		t.expect(layer(changes, refute(nil, answers, PATCH), nil)).toBe(nil)
		local older = layer(changes, refute(OLDER, answers, OTHER_PATCH), nil)
		t.expect(older ~= nil).toBe(true)
		t.expect(has(older, string.sub(FINISH, 1, 7))).toBe(true)
		-- no stamp in the refute leaves the review's own, which is older
		t.expect(layer(changes, refute(nil, answers), nil) ~= nil).toBe(true)
		-- a review of the current commit needs no stamp in its refute
		local current = review(FINISH, "changes", { "### F1 [medium] a thing" }, PATCH)
		t.expect(layer(current, refute(nil, { "- F1: fixed abc1234; consequences: none" }), nil)).toBe(nil)
	end)

	it(
		"AC3: a refute never carries an approve with no findings, nor an all-refuted review, to a changed patch",
		function()
			-- an approve with no findings has nothing to fix: a refute stamped with the new commit does not renew it
			local approve = review(OLDER, "approve", nil, OTHER_PATCH)
			t.expect(layer(approve, refute(FINISH, {}, PATCH), nil) ~= nil).toBe(true)
			-- a review whose findings are all refuted (and ruled by the human, so the answers are settled and only the
			-- currency is left to judge): the code did not change for them, so a refute cannot renew it
			local medium = review(OLDER, "changes", { "### F1 [medium] a thing" }, OTHER_PATCH)
			local ruled =
				"# c0010\n\n## Open to the human\n- F1: refuted by the author\n  Ruled (user, 2026-11-12): the refutation stands\n"
			t.expect(layer(medium, refute(FINISH, { "- F1: refuted: it is fine" }, PATCH), ruled) ~= nil)
				.toBe(true)
			-- the same review with its patch unchanged is complete: the ruling settles the answers
			t.expect(
				layer(
					review(OLDER, "changes", { "### F1 [medium] a thing" }, PATCH),
					refute(FINISH, { "- F1: refuted: it is fine" }, PATCH),
					ruled
				)
			).toBe(nil)
			-- nor one whose findings are all deferred
			t.expect(layer(medium, refute(FINISH, { "- F1: deferred c0099: later" }, PATCH), nil) ~= nil)
				.toBe(true)
			-- one fixed answer among others is enough
			local two = review(OLDER, "changes", { "### F1 [medium] a", "### F2 [medium] b" }, OTHER_PATCH)
			t.expect(
				layer(
					two,
					refute(
						FINISH,
						{ "- F1: deferred c0099: later", "- F2: fixed abc1234; consequences: none" },
						PATCH
					),
					nil
				)
			).toBe(nil)
		end
	)

	it("AC3: a missing stamp is not complete", function()
		local why = layer(review(nil, "approve", nil), nil, nil)
		t.expect(why ~= nil).toBe(true)
		t.expect(has(why, "Commit")).toBe(true)
		-- not even a refute that names the finish commit stands in for the review's own stamp
		local changes = review(nil, "changes", { "### F1 [medium] a thing" })
		t.expect(
			layer(changes, refute(FINISH, { "- F1: fixed abc1234; consequences: none" }, PATCH), nil) ~= nil
		)
			.toBe(true)
		-- a stamp far down the file is not a header
		local late = "# Review 001\n"
			.. string.rep("\nsome text", 30)
			.. "\n\nCommit: "
			.. FINISH
			.. "\nPatch: "
			.. PATCH
			.. "\nVerdict: approve\n"
		t.expect(layer(late, nil, nil) ~= nil).toBe(true)
		-- an empty finish commit or patch id fails closed
		t.expect(
			completion.layer({ finishSha = "", patchId = PATCH, review = review(FINISH, "approve", nil) })
				~= nil
		).toBe(true)
		t.expect(
			completion.layer({ finishSha = FINISH, patchId = "", review = review(FINISH, "approve", nil) })
				~= nil
		).toBe(true)
		-- completion.stamp puts the two lines in and keeps the ones a file has
		local stamped = completion.stamp("# Review 001\n\nVerdict: approve\n", FINISH, PATCH)
		t.expect(has(stamped, `Commit: {FINISH}`) and has(stamped, `Patch: {PATCH}`)).toBe(true)
		t.expect(layer(stamped, nil, nil)).toBe(nil)
		t.expect(completion.stamp(stamped, OLDER, OTHER_PATCH)).toBe(stamped)
	end)

	it("AC2: the final review rules are the same function (moved, not copied)", function()
		-- the same texts, judged as a final review and as a layer review, give the same answer
		local medium = review(FINISH, "changes", { "### F1 [medium] a thing" }, PATCH)
		local cases: { { r: string, a: string? } } = {
			{ r = medium, a = nil },
			{ r = medium, a = refute(nil, { "- F1: fixed abc1234: no consequences" }) },
			{ r = medium, a = refute(nil, { "- F1: fixed abc1234; consequences: none" }) },
			{ r = review(FINISH, "approve", nil, PATCH), a = nil },
			{
				r = review(FINISH, "changes", { "### F1 [high] bad" }, PATCH),
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
