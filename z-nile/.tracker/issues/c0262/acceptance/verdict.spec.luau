--!strict
-- c0262: reading the ticket's final reviews. A clear verdict, one redo, a second off-course blocks. Pure.
local finalview = require("@znile/engine/finalview")
local t = require("@tests/lib/t")

local function review(n: number, verdict: string, view: string, gaps: { string }): finalview.Review
	local measured: { boolean } = {}
	for _ in gaps do
		table.insert(measured, true)
	end
	return { n = n, verdict = verdict, view = view, findings = #gaps, gaps = gaps, measured = measured }
end

local function text(verdict: string, view: string, gaps: { string }): string
	local out = { "## Findings" }
	for i, g in gaps do
		table.insert(out, `### F{i}\nGap: {g}\nMeasured against: "x"\nwhat is wrong\n`)
	end
	table.insert(out, `View: {view}`)
	table.insert(out, `Verdict: {verdict}`)
	return table.concat(out, "\n") .. "\n"
end

return t.spec("c0262 the ticket's final verdict", function(it)
	it("AC4: a review is read into its verdict, its view and the Gap of each finding", function()
		local r = finalview.parse(2, text("off-course", "ab12", { "design", "implementation" }))
		t.expect(r.n).toBe(2)
		t.expect(r.verdict).toBe("off-course")
		t.expect(r.view).toBe("ab12")
		t.expect(r.findings).toBe(2)
		t.expect(r.gaps[1]).toBe("design")
		t.expect(r.gaps[2]).toBe("implementation")
		t.expect(finalview.problem(r)).toBe(nil)
		local ok = finalview.parse(1, text("on-course", "ab12", {}))
		t.expect(ok.verdict).toBe("on-course")
		t.expect(finalview.problem(ok)).toBe(nil)
	end)

	it(
		"AC4: a verdict nobody wrote, a gap nobody named and an on-course with findings are not read",
		function()
			t.expect(finalview.problem(finalview.parse(1, "## Findings\nnone\nView: ab\n")) ~= nil).toBe(true)
			t.expect(finalview.problem(finalview.parse(1, "View: ab\nVerdict: approve\n")) ~= nil).toBe(true)
			t.expect(finalview.problem(finalview.parse(1, "Verdict: on-course\n")) ~= nil).toBe(true)
			local nogap = finalview.parse(1, "### F1\nno gap line here\nView: ab\nVerdict: off-course\n")
			t.expect(finalview.problem(nogap) ~= nil).toBe(true)
			local nofinding = finalview.parse(1, "View: ab\nVerdict: off-course\n")
			t.expect(finalview.problem(nofinding) ~= nil).toBe(true)
			local contradictory = finalview.parse(1, text("on-course", "ab", { "design" }))
			t.expect(finalview.problem(contradictory) ~= nil).toBe(true)
		end
	)

	it("AC5: no review is none, an on-course review of this view is on-course", function()
		t.expect(finalview.state({}, "v1").state).toBe("none")
		t.expect(finalview.state({ review(1, "on-course", "v1", {}) }, "v1").state).toBe("on-course")
	end)

	it("AC5: an off-course review of this view sends the ticket back by the gap it names", function()
		t.expect(finalview.state({ review(1, "off-course", "v1", { "implementation" }) }, "v1").state)
			.toBe("redo-layer")
		t.expect(
			finalview.state({ review(1, "off-course", "v1", { "implementation", "design" }) }, "v1").state
		)
			.toBe("redo-design")
		t.expect(finalview.state({ review(1, "off-course", "v1", { "design" }) }, "v1").state)
			.toBe("redo-design")
	end)

	it("AC5: once the view changed after an off-course review, the review runs again", function()
		t.expect(finalview.state({ review(1, "off-course", "v1", { "design" }) }, "v2").state)
			.toBe("review-again")
		t.expect(finalview.state({ review(1, "on-course", "v1", {}) }, "v2").state).toBe("review-again")
	end)

	it("AC5: a second off-course verdict blocks the ticket, whatever the view", function()
		local two = {
			review(1, "off-course", "v1", { "design" }),
			review(2, "off-course", "v2", { "implementation" }),
		}
		t.expect(finalview.state(two, "v2").state).toBe("blocked")
		t.expect(finalview.state(two, "v3").state).toBe("blocked")
		-- the files in any order
		t.expect(finalview.state({ two[2] :: finalview.Review, two[1] :: finalview.Review }, "v2").state)
			.toBe("blocked")
	end)

	it("AC5: off, then on-course on the redone view, is on-course", function()
		local seq = { review(1, "off-course", "v1", { "implementation" }), review(2, "on-course", "v2", {}) }
		t.expect(finalview.state(seq, "v2").state).toBe("on-course")
	end)

	it("AC5: an unreadable review stops the ticket", function()
		local bad =
			{ n = 1, verdict = "", view = "v1", findings = 0, gaps = {}, measured = {} } :: finalview.Review
		t.expect(finalview.state({ bad }, "v1").state).toBe("invalid")
	end)

	it("AC4: a finding that quotes nothing, and a template Gap line, are not read", function()
		local nomeasure = finalview.parse(1, "### F1\nGap: design\nno quote\nView: ab\nVerdict: off-course\n")
		t.expect(finalview.problem(nomeasure) ~= nil).toBe(true)
		local placeholder = finalview.parse(
			1,
			'### F1\nGap: design\nMeasured against: "<the ask or design line>"\nView: ab\nVerdict: off-course\n'
		)
		t.expect(finalview.problem(placeholder) ~= nil).toBe(true)
		local template = finalview.parse(
			1,
			'### F1\nGap: design | implementation\nMeasured against: "the ask"\nView: ab\nVerdict: off-course\n'
		)
		t.expect(template.gaps[1]).toBe("")
		t.expect(finalview.problem(template) ~= nil).toBe(true)
		local approve = finalview.parse(1, "## Findings\nnone\nView: ab\nVerdict: approve\n")
		t.expect(finalview.problem(approve) ~= nil).toBe(true)
	end)

	it(
		"AC5: a review of a view an off-course review already judged is not read (reviewed again without a redo)",
		function()
			local same =
				{ review(1, "off-course", "v1", { "implementation" }), review(2, "on-course", "v1", {}) }
			t.expect(finalview.state(same, "v1").state).toBe("invalid")
			local twice = {
				review(1, "off-course", "v1", { "implementation" }),
				review(2, "off-course", "v1", { "design" }),
			}
			t.expect(finalview.state(twice, "v1").state).toBe("invalid")
		end
	)

	it(
		"AC5: the state says what the latest verdict was, so review-again after an off-course one is told apart",
		function()
			t.expect(finalview.state({ review(1, "off-course", "v1", { "design" }) }, "v2").latest)
				.toBe("off-course")
			t.expect(finalview.state({ review(1, "on-course", "v1", {}) }, "v2").latest).toBe("on-course")
			t.expect(finalview.state({}, "v1").latest).toBe("")
		end
	)

	-- c0262 with c0250: a blocked ticket is resolved by the human, and the ruling is read
	-- from c0250's note: the review it names, and the Decision of its Resolution.
	local TWICE = {
		review(1, "off-course", "v1", { "implementation" }),
		review(2, "off-course", "v2", { "implementation" }),
	}

	it("AC4: a gap's quote must be in the view it judged; a design gap quotes the ask", function()
		local files = {
			["ask.md"] = "# Ask: alpha\n\n## Problem (as captured)\n\nUser: the alpha value is **wrong**.\n",
			["design.md"] = "## Design\n\nalpha returns a `table`.\n",
			["design-changes.patch"] = "claims to check\n+ alpha returns a list.\n",
		}
		local function quoting(gap: string, quote: string): finalview.Review
			return finalview.parse(
				2,
				`### F1\nGap: {gap}\nMeasured against: "{quote}"\nmissing\n\nView: ab\nVerdict: off-course\n`
			)
		end
		t.expect(finalview.unquoted(quoting("design", "the alpha value is wrong"), files)).toBe(nil)
		t.expect(finalview.unquoted(quoting("implementation", "alpha returns a table"), files)).toBe(nil)
		t.expect(finalview.unquoted(quoting("implementation", "alpha returns a list."), files)).toBe(nil)
		t.expect(finalview.unquoted(quoting("implementation", "the alpha value is wrong"), files)).toBe(nil)
		-- made up, too short, or a design gap measured against the design itself
		t.expect(finalview.unquoted(quoting("design", "a line nobody wrote"), files) ~= nil).toBe(true)
		t.expect(finalview.unquoted(quoting("implementation", "x"), files) ~= nil).toBe(true)
		t.expect(finalview.unquoted(quoting("design", "alpha returns a table"), files) ~= nil).toBe(true)
	end)

	it(
		"AC11: another ticket review is filed only after the view changed, or once a retry set every review aside",
		function()
			t.expect(finalview.mayFileAgain("review-again")).toBe(true)
			t.expect(finalview.mayFileAgain("none")).toBe(true)
			for _, state in { "on-course", "redo-layer", "redo-design", "blocked", "invalid" } do
				t.expect(finalview.mayFileAgain(state)).toBe(false)
			end
		end
	)

	it("AC8: a blocked ticket's state names the latest review, the one the block's note names", function()
		local st = finalview.state(TWICE, "v2")
		t.expect(string.find(st.why, "final-review-002.md", 1, true) ~= nil).toBe(true)
	end)

	it(
		"AC14: a resolved block names the ticket's review it rules on; any other note rules on nothing",
		function()
			local n, d = finalview.ruling(
				"c0010",
				"c0010",
				"final-review-002.md\n### F1\nGap: implementation\n...",
				"approve"
			)
			t.expect(n).toBe(2)
			t.expect(d).toBe("approve")
			t.expect((finalview.ruling("c0010", "c0020", "final-review-002.md", "approve"))).toBe(nil)
			t.expect((finalview.ruling("c0010", "c0010", "final-review-002.md", nil))).toBe(nil)
			t.expect((finalview.ruling("c0010", "c0010", "the gate is red", "retry"))).toBe(nil)
		end
	)

	it("AC14: the human's approve of the blocking review puts the ticket on course on that view", function()
		t.expect(finalview.state(TWICE, "v2", { [2] = "approve" }).state).toBe("on-course")
		t.expect(finalview.state(TWICE, "v2", { [1] = "approve" }).state).toBe("redo-layer")
		-- an approve of another view is that view's: the moved layer is reviewed again
		t.expect(finalview.state(TWICE, "v3", { [2] = "approve" }).state).toBe("review-again")
	end)

	it("AC14: a retry sets the review aside, so it runs again and counts once", function()
		local st = finalview.state(TWICE, "v2", { [2] = "retry" })
		t.expect(st.state).toBe("review-again")
		t.expect(st.latest).toBe("off-course")
		t.expect(finalview.state({ TWICE[1] :: finalview.Review }, "v1", { [1] = "retry" }).state)
			.toBe("none")
		-- a third off-course verdict after the retry blocks again
		local three = table.clone(TWICE)
		table.insert(three, review(3, "off-course", "v3", { "implementation" }))
		t.expect(finalview.state(three, "v3", { [2] = "retry" }).state).toBe("blocked")
	end)

	it("AC14: the human's ruling lifts an unquoted review as it lifts an unreadable one", function()
		local bad = review(1, "off-course", "v1", { "implementation" })
		bad.unquoted = "final-review-001.md F1 quotes no line of ask.md, design.md or design-changes.patch"
		t.expect(finalview.state({ bad }, "v1").state).toBe("invalid")
		t.expect(finalview.state({ bad }, "v1", { [1] = "retry" }).state).toBe("none")
		t.expect(finalview.mayFileAgain(finalview.state({ bad }, "v1", { [1] = "retry" }).state)).toBe(true)
		t.expect(finalview.state({ bad }, "v1", { [1] = "approve" }).state).toBe("on-course")
	end)

	it(
		"AC14: an amend-design sends the ticket to z-design, and the next off-course verdict blocks again",
		function()
			t.expect(finalview.state(TWICE, "v2", { [2] = "amend-design" }).state).toBe("redo-design")
			-- a split takes the ticket out of its raft to be re-prepped, as an amend-design does
			t.expect(finalview.state(TWICE, "v2", { [2] = "split" }).state).toBe("redo-design")
			t.expect(
				string.find(finalview.state(TWICE, "v2", { [2] = "split" }).why, "resolve split", 1, true)
					~= nil
			).toBe(true)
			t.expect(finalview.state(TWICE, "v4", { [2] = "split" }).state).toBe("review-again")
			t.expect(finalview.state(TWICE, "v4", { [2] = "amend-design" }).state).toBe("review-again")
			local after = table.clone(TWICE)
			table.insert(after, review(3, "off-course", "v4", { "implementation" }))
			t.expect(finalview.state(after, "v4", { [2] = "amend-design" }).state).toBe("blocked")
			-- without a ruling the block holds, whatever the view
			t.expect(finalview.state(TWICE, "v9").state).toBe("blocked")
			t.expect(finalview.state(TWICE, "v9", { [2] = "abort" }).state).toBe("blocked")
		end
	)
end)
