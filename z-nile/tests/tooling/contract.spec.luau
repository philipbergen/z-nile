--!strict
-- The approval contract: what is hashed, what is not, and how a promotion still matches.
local contract = require("@znile/engine/contract")
local t = require("@tests/lib/t")

local DOC = [[---
id: c0001
type: chore
title: Hold
status: prepared-quiet-copper-falcon
design: ready
---

# c0001

## Problem
The gate cannot see an approval.

## Non-goals
Not hashed.

## Solution
Record a hash.

## Design
Hash the contract.

## Acceptance criteria
The hash is checked.

## Test plan
Specs cover the gates.

## Open to the human
- F1: a finding. Ruled (user, 2026-11-10): yes.

## Implementation steps
Not hashed.
]]

local CHECK = 'check "AC1: holds" true\n# z-nile/.tracker/issues/c0001/check.sh\n'
local SPEC = '--!strict\nlocal t = require("@tests/lib/t")\nreturn t.spec("holds", function() end)\n'

local function parts(doc: string, check: string, spec: string): contract.Parts
	local built, err = contract.build(doc, check, { ["hold.spec.luau"] = spec })
	if not built then
		error(err)
	end
	return built
end

return t.spec("the approval contract", function(it)
	it("normalises line endings and a missing trailing LF, and keeps other blank lines", function()
		t.expect(contract.normalize("a\r\nb\rc")).toBe("a\nb\nc\n")
		t.expect(contract.normalize("a\n\n")).toBe("a\n\n")
		t.expect(contract.normalize("")).toBe("")
	end)

	it("hashes the five design sections and leaves status, spend and the open list out", function()
		local base = contract.hash(parts(DOC, CHECK, SPEC))
		local stamped = (
			string.gsub(DOC, "status: prepared%-quiet%-copper%-falcon", "status: active-one-two-three")
		)
		t.expect(contract.hash(parts(stamped, CHECK, SPEC))).toBe(base)
		local ruled = (
			string.gsub(DOC, "Ruled %(user, 2026%-11%-10%): yes.", "Ruled (user, 2026-11-11): no.")
		)
		t.expect(contract.hash(parts(ruled, CHECK, SPEC))).toBe(base)
		local problem = (
			string.gsub(DOC, "The gate cannot see an approval.", "The gate must see an approval.")
		)
		t.expect(contract.hash(parts(problem, CHECK, SPEC)) == base).toBe(false)
	end)

	it("treats backlog, active and done check.sh paths as the same contract", function()
		local backlog = contract.hash(parts(DOC, CHECK, SPEC))
		local active = (string.gsub(CHECK, "/issues/c0001/", "/issues/active/c0001/"))
		local done = (string.gsub(CHECK, "/issues/c0001/", "/issues/done/c0001/"))
		t.expect(contract.hash(parts(DOC, active, SPEC))).toBe(backlog)
		t.expect(contract.hash(parts(DOC, done, SPEC))).toBe(backlog)
		local other = (string.gsub(CHECK, "holds", "fails"))
		t.expect(contract.hash(parts(DOC, other, SPEC)) == backlog).toBe(false)
	end)

	it("names the spec, the design or check.sh, and ignores a watch file's absence", function()
		local built = parts(DOC, CHECK, SPEC)
		local row: contract.Row = {
			when = "2026-11-11T00:00:00Z",
			who = "Ada",
			hash = contract.hash(built),
			parts = contract.partHashes(built),
		}
		t.expect(contract.changed(row, built)).toEqual({})
		local flipped = parts(DOC, CHECK, SPEC .. " ")
		t.expect(contract.changed(row, flipped)).toEqual({ "hold.spec.luau" })
		local edited = (string.gsub(DOC, "Hash the contract.", "Hash the contract now."))
		t.expect(contract.changed(row, parts(edited, CHECK, SPEC))).toEqual({ "design" })
		local check = (string.gsub(CHECK, "holds", "fails"))
		t.expect(contract.changed(row, parts(DOC, check, SPEC))).toEqual({ "check.sh" })
		local moved = parts(DOC, (string.gsub(CHECK, "/issues/c0001/", "/issues/done/c0001/")), SPEC)
		t.expect(contract.changed(row, moved)).toEqual({})
	end)

	it("keeps earlier rows and counts a re-approval", function()
		local built = parts(DOC, CHECK, SPEC)
		local function row(when: string): contract.Row
			return {
				when = when,
				who = "Ada",
				hash = contract.hash(built),
				parts = contract.partHashes(built),
			}
		end
		local text = contract.render({ row("2026-11-11T00:00:00Z"), row("2026-11-11T01:00:00Z") })
		local parsed, err = contract.parse(text)
		if not parsed then
			error(err)
		end
		t.expect(#parsed).toBe(2)
		t.expect(contract.reapprovals(parsed)).toBe(1)
		t.expect(parsed[1].who).toBe("Ada")
		t.expect(parsed[2].when).toBe("2026-11-11T01:00:00Z")
		local again = contract.render(parsed)
		t.expect(again).toBe(text)
	end)

	it("refuses an approval file that is not the header and four fields", function()
		local bad, err = contract.parse("# approval\nwhen\twho\thash\tparts\nnope\n")
		t.expect(bad).toBe(nil)
		t.expect(err ~= nil).toBe(true)
	end)
end)
