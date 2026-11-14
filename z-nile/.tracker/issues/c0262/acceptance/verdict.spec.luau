--!strict
-- c0262: reading the ticket's final reviews. A clear verdict, one redo, a second off-course blocks. Pure.
local finalview = require("@znile/engine/finalview")
local t = require("@tests/lib/t")

local function review(n: number, verdict: string, view: string, gaps: { string }): finalview.Review
	return { n = n, verdict = verdict, view = view, findings = #gaps, gaps = gaps }
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
		local bad = { n = 1, verdict = "", view = "v1", findings = 0, gaps = {} } :: finalview.Review
		t.expect(finalview.state({ bad }, "v1").state).toBe("invalid")
	end)
end)
