--!strict
-- c0262 AC1: the final review's limited view: the ask, the design, the check, the acceptance specs and the
-- implementation, and nothing of the execution. Pure: z-nile/engine/finalreview.luau.
local finalreview = require("@znile/engine/finalreview")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local DOC = table.concat({
	"---",
	"id: c0010",
	"type: chore",
	"title: Thing",
	"raft: R0099",
	"status: active-pink-blue-red",
	"---",
	"",
	"# c0010: Thing",
	"",
	"## Problem",
	"The ask, in the user's words.",
	"",
	"## Design",
	"Add a Foo module.",
	"",
	"## Acceptance criteria",
	"### Checked",
	"AC1: Foo exists.",
	"",
	"## Verification log",
	"2026-11-08: the author says it was easy; review-001 F3 refuted.",
	"",
}, "\n")

local function view(): { [string]: string }
	return finalreview.view({
		id = "c0010",
		ask = "CAPTURED ASK: make Foo",
		doc = DOC,
		check = "check \"AC1: Foo exists\" true",
		diff = "diff --git a/src/Foo.luau b/src/Foo.luau\n+local Foo = {}",
	})
end

return t.spec("c0262 AC1 the final review's limited view", function(it)
	it("AC1: the view is the ask, the design, the check and the implementation, and nothing of the execution", function()
		local v = view()
		local names = {}
		for name in v do
			table.insert(names, name)
		end
		table.sort(names)
		t.expect(names).toEqual({ "README.md", "ask.md", "check.sh", "design.md", "implementation.patch" })
		t.expect(has(v["ask.md"], "CAPTURED ASK: make Foo")).toBe(true)
		t.expect(has(v["design.md"], "Add a Foo module.")).toBe(true)
		t.expect(has(v["design.md"], "AC1: Foo exists.")).toBe(true)
		t.expect(has(v["implementation.patch"], "+local Foo = {}")).toBe(true)
		t.expect(has(v["check.sh"], "AC1")).toBe(true)
	end)

	it("AC1: the issue's acceptance specs ride in the view under acceptance/", function()
		local v = finalreview.view({
			id = "c0010",
			ask = "a",
			doc = DOC,
			check = "c",
			diff = "d",
			acceptance = { ["foo.spec.luau"] = "-- spec text" },
		})
		t.expect(v["acceptance/foo.spec.luau"]).toBe("-- spec text")
	end)

	it("AC1: the design drops the execution's own words (Verification log, status and raft lines)", function()
		local d = view()["design.md"]
		t.expect(has(d, "Verification log")).toBe(false)
		t.expect(has(d, "refuted")).toBe(false)
		t.expect(has(d, "status:")).toBe(false)
		t.expect(has(d, "raft:")).toBe(false)
		t.expect(has(d, "id: c0010")).toBe(true)
	end)

	it("AC1: the README of the view names the three comparisons and sends findings to the Off course line", function()
		local r = view()["README.md"]
		t.expect(has(r, "ask.md")).toBe(true)
		t.expect(has(r, "design.md")).toBe(true)
		t.expect(has(r, "implementation.patch")).toBe(true)
		t.expect(has(r, "Off course:")).toBe(true)
	end)

	it("AC1: the diff is limited to the issue's Touched modules and never takes tracker folders", function()
		local specs = finalreview.pathspecs({ "z-nile/engine/finalreview.luau", "z-nile/skills/zz-review" })
		t.expect(specs[1]).toBe("z-nile/engine/finalreview.luau")
		t.expect(specs[2]).toBe("z-nile/skills/zz-review")
		local joined = table.concat(specs, " ")
		t.expect(has(joined, ":(exclude,glob)**/.tracker/**")).toBe(true)
		-- an issue with no Touched modules gets the whole branch minus the tracker, never an empty diff
		local whole = finalreview.pathspecs(nil)
		t.expect(whole[1]).toBe(".")
		t.expect(has(table.concat(whole, " "), ":(exclude,glob)**/.tracker/**")).toBe(true)
	end)
end)
