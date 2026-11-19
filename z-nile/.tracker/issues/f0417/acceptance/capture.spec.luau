--!strict
-- f0417 AC4: c0260's record check (z-nile/engine/capturecheck.luau, as c0260 lands it) takes the guess-mode
-- Confirmation on a marked issue with exactly its grammar and binding: `Unconfirmed (guess mode, YYYY-MM-DD) after
-- round N: <words>`, first (a person's Confirmed line may follow it), bound to the last idea round like any other line;
-- an unmarked issue keeps c0260's rule (an Unconfirmed line is only ever unattended). Pure.
local capturecheck = require("@znile/engine/capturecheck")
local t = require("@tests/lib/t")

local function any(list: { string }, needle: string): boolean
	for _, line in list do
		if string.find(line, needle, 1, true) then
			return true
		end
	end
	return false
end

local REVIEW =
	"# Idea review 002\nRound: ask 1, interview 1, idea abc123\n\n## Findings\n- F1: none\n\n## Verdict\napprove\n"
local REVIEWS = { ["idea-review-001.md"] = REVIEW, ["idea-review-002.md"] = REVIEW }
local GUESS =
	"Unconfirmed (guess mode, 2026-11-20) after round 2: carried by z-work; the person's ./zn approve confirms it"

local function doc(marked: boolean, confirmation: string): string
	return "---\nid: c0002\ncapture: required\nidea: challenged\n"
		.. (if marked then "rounds: on\n" else "")
		.. "status: preparing-brisk-plucky-amber\n---\n\n# c0002\n\n## Problem\n- p.\n\n## Ask (verbatim)\n### Message 2026-11-18\n```\nmake it louder\n```\n\n## Interview\n### Q1\nwhich?\nA: this.\n\n## Confirmation\n"
		.. confirmation
		.. "\n"
end

return t.spec("f0417: c0260's record check and the guess-mode Confirmation", function(it)
	it("a marked issue's guess-mode line, bound to the last round, passes the record check", function()
		local problems = capturecheck.check(doc(true, GUESS), REVIEWS)
		t.expect(any(problems, "Unconfirmed is only ever")).toBe(false)
		t.expect(any(problems, "Confirmation follows round")).toBe(false)
		t.expect(any(problems, "Confirmation lines read")).toBe(false)
		t.expect(any(problems, "onfirm")).toBe(false) -- no Confirmation problem of any kind
	end)

	it(
		"a change of the record drops the guess-mode line as it drops a Confirmed line, so it never goes stale or doubles",
		function()
			local dropped = capturecheck.dropConfirmed(doc(true, GUESS))
			t.expect((string.find(dropped, "guess mode", 1, true))).toBe(nil)
			local both = capturecheck.dropConfirmed(
				doc(true, GUESS .. '\nConfirmed (Ada, 2026-11-21) after round 2: "yes"')
			)
			t.expect((string.find(both, "guess mode", 1, true))).toBe(nil)
			t.expect((string.find(both, "Confirmed (Ada", 1, true))).toBe(nil)
			-- an unattended line stays, as c0260 lands it
			local unattended = "Unconfirmed (unattended, 2026-11-20) after round 2: nobody was asked"
			t.expect(
				string.find(capturecheck.dropConfirmed(doc(true, unattended)), "unattended", 1, true) ~= nil
			)
				.toBe(true)
		end
	)

	it("an unmarked issue keeps c0260's rule, and the line keeps its round binding and its place", function()
		t.expect(any(capturecheck.check(doc(false, GUESS), REVIEWS), "Unconfirmed is only ever")).toBe(true)
		local stale = (string.gsub(GUESS, "after round 2", "after round 1"))
		t.expect(any(capturecheck.check(doc(true, stale), REVIEWS), "Confirmation follows round 1"))
			.toBe(true)
		-- the person's Confirmed line may follow it; it may not follow the Confirmed line
		local confirmed = 'Confirmed (Ada, 2026-11-21) after round 2: "yes"'
		local after = capturecheck.check(doc(true, GUESS .. "\n" .. confirmed), REVIEWS)
		t.expect(any(after, "Unconfirmed is only ever")).toBe(false)
		t.expect(any(after, "an Unconfirmed line comes first")).toBe(false)
		t.expect(any(capturecheck.check(doc(true, confirmed .. "\n" .. GUESS), REVIEWS), "comes first"))
			.toBe(true)
	end)

	it(
		"c0260's other rules stand on a marked issue: two Confirmed lines refused, the unattended line accepted",
		function()
			local confirmed = 'Confirmed (Ada, 2026-11-21) after round 2: "yes"'
			t.expect(
				any(
					capturecheck.check(doc(true, confirmed .. "\n" .. confirmed), REVIEWS),
					"Confirmation holds one line"
				)
			).toBe(true)
			local unattended = "Unconfirmed (unattended, 2026-11-20) after round 2: nobody was asked"
			t.expect(any(capturecheck.check(doc(true, unattended), REVIEWS), "Unconfirmed is only ever"))
				.toBe(false)
		end
	)

	it("a record change may drop a marked issue's guess-mode line, as it drops a Confirmed line", function()
		local old = doc(true, GUESS)
		local new = (string.gsub(old, "\n## Confirmation\n[^\n]*\n", "\n## Confirmation\n"))
		t.expect(capturecheck.recordGrows(old, new)).toBe(true)
		local oldUnmarked = doc(false, GUESS)
		local newUnmarked = (string.gsub(oldUnmarked, "\n## Confirmation\n[^\n]*\n", "\n## Confirmation\n"))
		t.expect(capturecheck.recordGrows(oldUnmarked, newUnmarked)).toBe(false)
	end)
end)
