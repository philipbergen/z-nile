--!strict
-- f0399: guesses.md, the approval part that covers it, and a guessed answer under "Open to the human". Pure.
local contract = require("@znile/engine/contract")
local guesses = require("@znile/engine/guesses")
local openlist = require("@znile/engine/openlist")
local t = require("@tests/lib/t")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local DOC = [[---
id: c0001
design: ready
---

# c0001

## Problem
p

## Solution
s

## Design
d

## Acceptance criteria
a

## Test plan
t
]]

local function open(body: string): string
	return DOC .. "\n## Open to the human\n" .. body
end

return t.spec("f0399: guesses and what covers them", function(it)
	it("append numbers from G1 and parse reads back what was written", function()
		local one, e1 =
			guesses.append(nil, "design", "2026-11-16", "Which file holds it.", "guesses.md.", "One list.")
		t.expect(e1).toBe(nil)
		t.expect(one)
			.toBe("# guesses\n- G1 (design, 2026-11-16): Which file holds it. Chose: guesses.md. Why: One list.\n")
		local two = guesses.append(
			one,
			"build",
			"2026-11-17",
			"Retry count.",
			"Two.",
			"The skill says a real second attempt."
		)
		local list = guesses.parse(two :: string) :: { guesses.Guess }
		t.expect(#list).toBe(2)
		t.expect(list[2].id).toBe("G2")
		t.expect(list[2].step).toBe("build")
		t.expect(list[2].when).toBe("2026-11-17")
		t.expect(list[2].open).toBe("Retry count.")
		t.expect(list[2].chose).toBe("Two.")
		t.expect(list[2].why).toBe("The skill says a real second attempt.")
		t.expect(guesses.render(list)).toBe(two)
		t.expect(guesses.has(two, "G2")).toBe(true)
		t.expect(guesses.has(two, "G3")).toBe(false)
		t.expect(guesses.has(nil, "G1")).toBe(false)
	end)

	it("append refuses an unknown step, an empty field, a line break and a mark in a field", function()
		local function refused(step: string, o: string, c: string, w: string): string
			local text, err = guesses.append(nil, step, "2026-11-16", o, c, w)
			t.expect(text).toBe(nil)
			return err :: string
		end
		t.expect(has(refused("review", "o", "c", "w"), 'unknown step "review"')).toBe(true)
		t.expect(has(refused("design", " ", "c", "w"), "--open is empty")).toBe(true)
		t.expect(has(refused("design", "o", "", "w"), "--chose is empty")).toBe(true)
		t.expect(has(refused("design", "o", "c", ""), "--why is empty")).toBe(true)
		t.expect(has(refused("design", "o\nx", "c", "w"), "--open has a line break")).toBe(true)
		t.expect(has(refused("design", "o", "c Why: x", "w"), "--chose holds a mark")).toBe(true)
		t.expect(has(refused("design", "o Chose: x", "c", "w"), "--open holds a mark")).toBe(true)
		local text, err = guesses.append("not a guesses file\n", "design", "2026-11-16", "o", "c", "w")
		t.expect(text).toBe(nil)
		t.expect(has(err, "guesses.md does not parse")).toBe(true)
	end)

	it(
		"parse refuses a missing header, a gap in the numbers, an unknown step and a line that is not a guess",
		function()
			local function bad(text: string): string
				local list, err = guesses.parse(text)
				t.expect(list).toBe(nil)
				return err :: string
			end
			t.expect(has(bad("- G1 (design, 2026-11-16): o Chose: c Why: w\n"), "first line")).toBe(true)
			t.expect(has(bad("# guesses\n- G2 (design, 2026-11-16): o Chose: c Why: w\n"), "expected G1"))
				.toBe(true)
			t.expect(has(bad("# guesses\n- G1 (review, 2026-11-16): o Chose: c Why: w\n"), "unknown step"))
				.toBe(true)
			t.expect(has(bad("# guesses\n- G1 (design, 2026-11-16): o Why: w\n"), "Chose: ")).toBe(true)
			t.expect(has(bad("# guesses\nsome prose\n"), "is not a guess")).toBe(true)
			local empty = guesses.parse("# guesses\n") :: { guesses.Guess }
			t.expect(#empty).toBe(0)
		end
	)

	it("extends accepts added guesses and refuses a removed, changed or unreadable one", function()
		local g1 = "# guesses\n- G1 (design, 2026-11-16): o Chose: c Why: w\n"
		local g2 = guesses.append(g1, "build", "2026-11-17", "o2", "c2", "w2") :: string
		t.expect(guesses.extends(nil, nil)).toBe(true)
		t.expect(guesses.extends(nil, g1)).toBe(true)
		t.expect(guesses.extends(g1, g1)).toBe(true)
		t.expect(guesses.extends(g1, g2)).toBe(true)
		t.expect(guesses.extends(g2, g1)).toBe(false)
		t.expect(guesses.extends(g1, nil)).toBe(false)
		t.expect(guesses.extends(g1, "")).toBe(false)
		t.expect(guesses.extends(g1, "# guesses\n- G1 (design, 2026-11-16): o Chose: other Why: w\n"))
			.toBe(false)
		t.expect(guesses.extends(g1, "# guesses\n- G1 (build, 2026-11-16): o Chose: c Why: w\n")).toBe(false)
		t.expect(guesses.extends(g1, "not a guesses file\n")).toBe(false)
		t.expect(guesses.extends(nil, "not a guesses file\n")).toBe(false)
	end)

	it("the contract has a guesses part only when guesses.md has text", function()
		local specs = { ["hold.spec.luau"] = "return 1\n" }
		local plain = contract.build(DOC, "check\n", specs) :: contract.Parts
		local none = contract.build(DOC, "check\n", specs, nil) :: contract.Parts
		local blank = contract.build(DOC, "check\n", specs, "") :: contract.Parts
		t.expect(plain.guesses).toBe(nil)
		t.expect(contract.hash(none)).toBe(contract.hash(plain))
		t.expect(contract.hash(blank)).toBe(contract.hash(plain))
		local with = contract.build(
			DOC,
			"check\n",
			specs,
			"# guesses\n- G1 (design, 2026-11-16): o Chose: c Why: w\n"
		) :: contract.Parts
		t.expect(with.guesses ~= nil).toBe(true)
		t.expect(contract.hash(with) ~= contract.hash(plain)).toBe(true)
		t.expect(contract.order(with)).toEqual({ "design", "check.sh", "guesses", "hold.spec.luau" })
	end)

	it("an approval made before a guess no longer holds after it, and the changed part is guesses", function()
		local g1 = "# guesses\n- G1 (design, 2026-11-16): o Chose: c Why: w\n"
		local before = contract.build(DOC, "check\n", {}, g1) :: contract.Parts
		local row: contract.Row = {
			when = "2026-11-16T00:00:00Z",
			who = "Ada",
			hash = contract.hash(before),
			parts = contract.partHashes(before),
		}
		t.expect(contract.changed(row, before)).toEqual({})
		local g2 = guesses.append(g1, "build", "2026-11-17", "o2", "c2", "w2") :: string
		local after = contract.build(DOC, "check\n", {}, g2) :: contract.Parts
		t.expect(contract.changed(row, after)).toEqual({ "guesses" })
		-- a first guess after an approval that had none
		local bare = contract.build(DOC, "check\n", {}) :: contract.Parts
		local bareRow: contract.Row =
			{ when = row.when, who = "Ada", hash = contract.hash(bare), parts = contract.partHashes(bare) }
		t.expect(contract.changed(bareRow, before)).toEqual({ "guesses" })
	end)

	it("a spec named guesses cannot be hashed", function()
		local parts, err = contract.build(DOC, "check\n", { guesses = "x" })
		t.expect(parts).toBe(nil)
		t.expect(has(err, 'cannot be hashed: "guesses"')).toBe(true)
	end)

	it("a Guessed bullet is not waiting and is still pending", function()
		local doc = open(
			"- F1: a refuted finding. Decision: rule it.\n  Guessed (agent, 2026-11-16): G3\n- F2: another. Decision: rule it.\n- JC1: failed. Ruled (user, 2026-11-10): accepted.\n"
		)
		t.expect(openlist.pending(doc)).toEqual({ "F1", "F2" })
		t.expect(openlist.waiting(doc)).toEqual({ "F2" })
		local review = "### F1 [high] a\n\n### F2 [high] b\n"
		local refute = "- F1: refuted: no\n- F2: refuted: no\n"
		t.expect(has(openlist.problem(review, refute, doc), "open to the human (F2)")).toBe(true)
		local both = open(
			"- F1: a. Decision: rule it.\n  Guessed (agent, 2026-11-16): G3\n- F2: b.\n  Guessed (agent, 2026-11-16): G4\n"
		)
		t.expect(openlist.problem(review, refute, both)).toBe(nil)
	end)

	it("guessed reads the guess and the issue a Guessed line names, and skips a ruled bullet", function()
		local doc = open(
			"- F1: a.\n  Guessed (agent, 2026-11-16): G3\n- F2: b. Guessed (agent, 2026-11-16): c0010 G1\n- F3: c.\n  Guessed (agent, 2026-11-16): G9\n  Ruled (user, 2026-11-17): no, do it the other way.\n- F4: d.\n  Guessed (agent, 2026-11-16): see above\n"
		)
		local got = openlist.guessed(doc)
		t.expect(#got).toBe(3)
		t.expect(got[1]).toEqual({ id = "F1", guess = "G3" })
		t.expect(got[2]).toEqual({ id = "F2", issue = "c0010", guess = "G1" })
		t.expect(got[3]).toEqual({ id = "F4", guess = "" })
		t.expect(openlist.waiting(doc)).toEqual({})
		t.expect(openlist.guessed(DOC)).toEqual({})
	end)
end)
