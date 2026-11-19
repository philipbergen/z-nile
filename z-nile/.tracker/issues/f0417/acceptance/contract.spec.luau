--!strict
-- f0417 AC6: the contract a person approves names the idea (for a marked issue) and the assumptions, each a part of
-- its own and each only when it has text, so an approval recorded before keeps its hash. Pure.
local contract = require("@znile/engine/contract")
local t = require("@tests/lib/t")

local DOC = [[---
id: c0001
design: ready
rounds: on
---

# c0001

## Problem
p

## Non-goals
- n.

## Solution
s

## Ask (verbatim)
### Message 2026-11-18
make it louder

## Interview
### Q1
which ghost?

## Confirmation
Unconfirmed (guess mode, 2026-11-18) after round 2: carried by z-work; the person's ./zn approve confirms it

## Design
d

## Acceptance criteria
a

## Test plan
t
]]

local SPECS = { ["x.spec.luau"] = "return 1\n" }
local CHECK = 'check "AC1: x" true\n'
local GUESSES = "# guesses\n- G1 (design, 2026-11-18): a Chose: b Why: c\n"
local ASSUME = "# assumptions\n- A1 (design, 2026-11-18): a Because: b Unproven: c\n"
local FILES = {
	["idea-review-002.md"] = "# Idea review 002\n\n## Findings\n- F1: none\n\n## Verdict\napprove\n",
	["idea-refute-001.md"] = "# Idea refute 001\n\n- F1: revised\n",
	["idea-review-001.md"] = "# Idea review 001\n\n## Findings\n- F1: too big.\n\n## Verdict\nrevise\n",
	["notes.md"] = "not an idea file\n",
}

local function names(parts: contract.Parts): { string }
	return contract.order(parts)
end

return t.spec("f0417: the idea and the assumptions in the contract", function(it)
	it("the idea and the assumptions are parts of their own, after guesses", function()
		local idea = contract.ideaText(DOC, FILES)
		local parts =
			contract.build(DOC, CHECK, SPECS, GUESSES, { idea = idea, assumptions = ASSUME }) :: contract.Parts
		t.expect(names(parts))
			.toEqual({ "design", "check.sh", "guesses", "idea", "assumptions", "x.spec.luau" })
		t.expect(parts.assumptions).toBe(contract.normalize(ASSUME))
		t.expect(parts.idea).toBe(contract.normalize(idea))
	end)

	it("an approval recorded before keeps its hash", function()
		local before = contract.build(DOC, CHECK, SPECS, GUESSES) :: contract.Parts
		local same = contract.build(DOC, CHECK, SPECS, GUESSES, nil) :: contract.Parts
		local empty =
			contract.build(DOC, CHECK, SPECS, GUESSES, { idea = "", assumptions = "  \n" }) :: contract.Parts
		local none = contract.build(DOC, CHECK, SPECS, GUESSES, {}) :: contract.Parts
		t.expect(contract.hash(same)).toBe(contract.hash(before))
		t.expect(contract.hash(empty)).toBe(contract.hash(before))
		t.expect(contract.hash(none)).toBe(contract.hash(before))
		t.expect(empty.idea).toBe(nil)
		t.expect(empty.assumptions).toBe(nil)
	end)

	it(
		"ideaText holds the ask, the interview, the non-goals and every idea review and refute, in order",
		function()
			local text = contract.ideaText(DOC, FILES)
			local function at(needle: string): number
				return string.find(text, needle, 1, true) or error(`ideaText is missing: {needle}`)
			end
			local ng, ask, iv = at("- n."), at("make it louder"), at("which ghost?")
			t.expect(at("Unconfirmed (guess mode, 2026-11-18)") > iv).toBe(true)
			local r1, f1, r2 =
				at("## idea-refute-001.md"), at("## idea-review-001.md"), at("## idea-review-002.md")
			t.expect(ng < ask and ask < iv and iv < r1).toBe(true)
			t.expect(r1 < f1 and f1 < r2).toBe(true) -- name order: refute-001, review-001, review-002
			t.expect(string.find(text, "too big.", 1, true) ~= nil).toBe(true)
			t.expect((string.find(text, "not an idea file", 1, true))).toBe(nil)
			t.expect((string.find(text, "## Problem", 1, true))).toBe(nil) -- already in the design part
			t.expect(contract.ideaText("## Problem\np\n", {})).toBe("")
		end
	)

	it("a changed idea review or assumption changes its part only", function()
		local base = contract.build(DOC, CHECK, SPECS, GUESSES, {
			idea = contract.ideaText(DOC, FILES),
			assumptions = ASSUME,
		}) :: contract.Parts
		local row: contract.Row = {
			when = "2026-11-18T00:00:00Z",
			who = "Ada",
			hash = contract.hash(base),
			parts = contract.partHashes(base),
		}
		local files2 = table.clone(FILES)
		files2["idea-refute-001.md"] = "# Idea refute 001\n\n- F1: disputed: no\n"
		local changedIdea = contract.build(DOC, CHECK, SPECS, GUESSES, {
			idea = contract.ideaText(DOC, files2),
			assumptions = ASSUME,
		}) :: contract.Parts
		t.expect(contract.changed(row, changedIdea)).toEqual({ "idea" })
		local more = ASSUME .. "- A2 (build, 2026-11-19): d Because: e Unproven: f\n"
		local changedA = contract.build(DOC, CHECK, SPECS, GUESSES, {
			idea = contract.ideaText(DOC, FILES),
			assumptions = more,
		}) :: contract.Parts
		t.expect(contract.changed(row, changedA)).toEqual({ "assumptions" })
	end)

	it(
		"more decides the extra parts: the idea only for a marked issue, the assumptions whenever written",
		function()
			local files = table.clone(FILES)
			files["assumptions.md"] = ASSUME
			local m = contract.more(DOC, files)
			t.expect(m.idea).toBe(contract.ideaText(DOC, files))
			t.expect(m.assumptions).toBe(ASSUME)
			local unmarked = (string.gsub(DOC, "rounds: on\n", ""))
			local u = contract.more(unmarked, files)
			t.expect(u.idea).toBe(nil)
			t.expect(u.assumptions).toBe(ASSUME)
			local bare = contract.more(DOC, {})
			t.expect(bare.assumptions).toBe(nil)
			-- an unmarked issue's contract with its idea files present hashes as before
			local before = contract.build(unmarked, CHECK, SPECS, GUESSES) :: contract.Parts
			local now =
				contract.build(unmarked, CHECK, SPECS, GUESSES, contract.more(unmarked, FILES)) :: contract.Parts
			t.expect(contract.hash(now)).toBe(contract.hash(before))
		end
	)

	it("idea and assumptions are not spec names", function()
		for _, name in { "idea", "assumptions" } do
			local parts, why = contract.build(DOC, CHECK, { [name] = "x" }, nil)
			t.expect(parts).toBe(nil)
			t.expect(string.find(why or "", name, 1, true) ~= nil).toBe(true)
		end
	end)
end)
