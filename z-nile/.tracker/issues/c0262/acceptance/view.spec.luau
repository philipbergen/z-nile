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

local function view(over: { [string]: any }?): { [string]: string }
	local input: { [string]: any } = {
		id = "c0010",
		ask = "CAPTURED ASK: make Foo",
		doc = DOC,
		designChanges = "",
		check = 'check "AC1: Foo exists" true',
		diff = "diff --git a/src/Foo.luau b/src/Foo.luau\n+local Foo = {}",
		skill = "# Adversarial review\nFinal mode ... Verdict: approve | changes ... Off course:",
	}
	for k, v in over or {} do
		input[k] = v
	end
	return finalreview.view(input :: any)
end

return t.spec("c0262 AC1 the final review's limited view", function(it)
	it("AC1: the view holds the ask, the design, the design's branch edits, the check, the skill and the diff, and nothing else", function()
		local names = {}
		for name in view() do
			table.insert(names, name)
		end
		table.sort(names)
		t.expect(names).toEqual({
			"README.md",
			"ask.md",
			"check.sh",
			"design-changes.patch",
			"design.md",
			"implementation.patch",
			"skill.md",
		})
		local v = view()
		t.expect(has(v["ask.md"], "CAPTURED ASK: make Foo")).toBe(true)
		t.expect(has(v["design.md"], "Add a Foo module.")).toBe(true)
		t.expect(has(v["implementation.patch"], "+local Foo = {}")).toBe(true)
		t.expect(has(v["skill.md"], "Off course:")).toBe(true)
	end)

	it("AC1: acceptance specs ride under acceptance/, and design edits made on the branch ride as claims to check", function()
		local v = view({
			acceptance = { ["foo.spec.luau"] = "-- spec text" },
			designChanges = "+Scope decision (user, 2026-11-09): \"skip it\"",
		})
		t.expect(v["acceptance/foo.spec.luau"]).toBe("-- spec text")
		t.expect(has(v["design-changes.patch"], "Scope decision (user, 2026-11-09)")).toBe(true)
		-- the README says a line added on the branch is a claim, not a decision
		t.expect(has(v["README.md"], "claim")).toBe(true)
		t.expect(has(v["README.md"], "design-changes.patch")).toBe(true)
	end)

	it("AC1: the design drops the execution's own words (Verification log, status and raft lines)", function()
		local d = view()["design.md"]
		t.expect(has(d, "Verification log")).toBe(false)
		t.expect(has(d, "refuted")).toBe(false)
		t.expect(has(d, "status:")).toBe(false)
		t.expect(has(d, "raft:")).toBe(false)
		t.expect(has(d, "id: c0010")).toBe(true)
	end)

	it("AC1: the README names the comparisons, the skill and the Off course tag, and never a repository path", function()
		local r = view()["README.md"]
		for _, word in { "ask.md", "design.md", "implementation.patch", "skill.md", "Off course:" } do
			t.expect(has(r, word)).toBe(true)
		end
		t.expect(has(r, "z-nile/")).toBe(false)
	end)

	it("AC1: the README names the other members whose Touched modules overlap, and marks an emergent member", function()
		local r = view({
			others = { { id = "c0011", paths = { "z-nile/engine/main.luau" } } },
			emergent = true,
		})["README.md"]
		t.expect(has(r, "c0011")).toBe(true)
		t.expect(has(r, "z-nile/engine/main.luau")).toBe(true)
		t.expect(has(r, "emergent")).toBe(true)
		local alone = view()["README.md"]
		t.expect(has(alone, "c0011")).toBe(false)
		t.expect(has(alone, "emergent")).toBe(false)
	end)

	it("AC1: an empty implementation diff refuses to build a view", function()
		local ok, e = pcall(view, { diff = "" })
		t.expect(ok).toBe(false)
		t.expect(has(tostring(e), "empty")).toBe(true)
	end)

	it("AC1: the diff is limited to the Touched modules and excludes only the raft's and the issue's own folders", function()
		local specs = finalreview.pathspecs(
			{ "z-nile/engine/finalreview.luau", "pickman/.tracker/architecture.md" },
			{ "z-nile/.tracker/rafts/active/R0099", "z-nile/.tracker/issues/active/c0010" }
		)
		t.expect(specs[1]).toBe("z-nile/engine/finalreview.luau")
		t.expect(specs[2]).toBe("pickman/.tracker/architecture.md")
		t.expect(specs[3]).toBe(":(exclude)z-nile/.tracker/rafts/active/R0099")
		t.expect(specs[4]).toBe(":(exclude)z-nile/.tracker/issues/active/c0010")
		t.expect(#specs).toBe(4)
		-- an issue with no Touched modules gets the whole branch minus those two folders
		local whole = finalreview.pathspecs(nil, { "a/raft", "a/issue" })
		t.expect(whole).toEqual({ ".", ":(exclude)a/raft", ":(exclude)a/issue" })
	end)
end)
