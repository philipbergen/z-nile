--!strict
-- c0181 AC12: a rule is a pure check the tool runs at the moment a mistake would be made (`./zn status <id> prepared`,
-- `ready`, `land`, `done`, `commit`, `spend`, `audit`, a rewrite), over a view the command builds:
-- `z-nile/engine/rules.luau` (`define`, `check`, `reports`, `selfTest`, `applies`) and one module per rule in
-- `z-nile/engine/rules/`, each listed in `z-nile/engine/rules/registry.luau` as `{ path, rule }`. A rule that needs
-- something to be present (a stamp, a section) judges a design only when its document's `### Rules and mutants`
-- table has a data row (the template `./zn new` writes has the header only, so no stub item is judged); a rule that
-- refuses a bad thing judges everything. A rule names its lesson, proves itself on a `bad` and a `good` view, and is
-- cleared per item by that item's `lint-allow.md`. `./zn prove` writes a proof stamp whose pure part is pinned here.
local engine = require("@tests/lib/engine")
local fs = require("@lune/fs")
local lessons = require("@znile/engine/lessons")
local prove = require("@znile/engine/prove")
local registry = require("@znile/engine/rules/registry")
local rules = require("@znile/engine/rules")
local t = require("@tests/lib/t")

local ID = "z-design/no-todo-in-design"
local ROW =
	"### Rules and mutants\n| rule | spec :: case | mutant it kills | checked |\n|---|---|---|---|\n| a | b | c | run |\n"
local HEAD = "### Rules and mutants\n| rule | spec :: case | mutant it kills | checked |\n|---|---|---|---|\n"
local function doc(table: string, body: string): string
	return `---\nid: c0900\ndesign: ready\n---\n# c0900\n\n{table}\n{body}\n`
end
local function view(files: { [string]: string }, hook: string?): rules.View
	return { hook = hook or "prepared", id = "c0900", files = files } :: rules.View
end
local function rule(extra: { [string]: any }?): rules.Rule
	local r: any = {
		lesson = ID,
		hook = "prepared",
		presence = true,
		check = function(v: rules.View): { string }
			local out = {}
			if string.find(v.files["c0900.md"] or "", "TODO", 1, true) then
				table.insert(out, "the design still has a TODO")
			end
			return out
		end,
		bad = view({ ["c0900.md"] = doc(ROW, "TODO later") }),
		good = view({ ["c0900.md"] = doc(ROW, "done") }),
	}
	if extra then
		for k, v in extra do
			r[k] = v
		end
	end
	return r :: rules.Rule
end

return t.spec("c0181 rules at the moment of the mistake", function(it)
	it("a rule names its lesson in every problem and proves itself on a bad and a good view", function()
		local r = rule()
		t.expect(rules.check({ r }, view({ ["c0900.md"] = doc(ROW, "TODO later") }))).toEqual({
			`lesson {ID}: the design still has a TODO`,
		})
		t.expect(rules.selfTest(r)).toEqual({})
		local blind = rules.selfTest(rule({
			check = function(): { string }
				return {}
			end,
		}))
		t.expect(#blind >= 1).toBe(true)
		t.expect(string.find(blind[1], ID, 1, true) ~= nil).toBe(true)
	end)

	it("only the rules of the hook run, and a lesson may have a rule at two hooks", function()
		local design = view({ ["c0900.md"] = doc(ROW, "TODO later") })
		t.expect(rules.check({ rule() }, view(design.files, "ready"))).toEqual({})
		local both = { rule(), rule({ hook = "ready" }) }
		t.expect(#rules.check(both, design)).toBe(1)
		t.expect(#rules.check(both, view(design.files, "ready"))).toBe(1)
	end)

	it("a presence rule judges only a document whose Rules and mutants table has a data row", function()
		local bare = doc(HEAD, "TODO later") -- what `./zn new` writes: the header and the separator, no row
		t.expect(rules.applies(rule(), view({ ["c0900.md"] = bare }))).toBe(false)
		t.expect(rules.check({ rule() }, view({ ["c0900.md"] = bare }))).toEqual({})
		t.expect(rules.applies(rule(), view({ ["c0900.md"] = doc(ROW, "") }))).toBe(true)
		-- an absence rule judges every document
		t.expect(rules.applies(rule({ presence = false }), view({ ["c0900.md"] = bare }))).toBe(true)
		t.expect(#rules.check({ rule({ presence = false }) }, view({ ["c0900.md"] = bare }))).toBe(1)
	end)

	it("the document `./zn new` renders has no data row, whatever design: it sets", function()
		local template = fs.readFile(`{engine.TOP}/z-nile/templates/issue/doc.md`)
		local ready = string.gsub(template, "design: draft", "design: ready")
		t.expect(rules.applies(rule(), view({ ["c0900.md"] = ready }))).toBe(false)
	end)

	it("a report rule prints and never refuses", function()
		local note = rule({ report = true })
		local v = view({ ["c0900.md"] = doc(ROW, "TODO later") })
		t.expect(rules.check({ note }, v)).toEqual({})
		t.expect(#rules.reports({ note }, v)).toBe(1)
	end)

	it("an item's lint-allow.md clears that lesson's problems for that item and no other lesson's", function()
		local files = { ["c0900.md"] = doc(ROW, "TODO later") }
		local function with(allow: string): { [string]: string }
			return { ["c0900.md"] = files["c0900.md"], ["lint-allow.md"] = allow }
		end
		t.expect(rules.check({ rule() }, view(with("- z-design/no-todo-in-design: mid-prep, sequestered\n"))))
			.toEqual({})
		t.expect(#rules.check({ rule() }, view(with("- z-design/other: a reason\n")))).toBe(1)
		t.expect(#rules.check({ rule() }, view(with("- z-design/no-todo-in-design:\n")))).toBe(1)
	end)

	it(
		"a baseline line that clears nothing is a problem where the view can be built from the folder",
		function()
			local clean = view({
				["c0900.md"] = doc(ROW, "done"),
				["lint-allow.md"] = "- z-design/no-todo-in-design: a reason\n",
			})
			t.expect(#rules.baseline(rule(), clean)).toBe(1)
			local live = view({
				["c0900.md"] = doc(ROW, "TODO"),
				["lint-allow.md"] = "- z-design/no-todo-in-design: a reason\n",
			})
			t.expect(rules.baseline(rule(), live)).toEqual({})
		end
	)

	it("a prepared rule run for a member at ready is a report, never a refusal", function()
		local member = view({ ["c0900.md"] = doc(ROW, "TODO later") }, "prepared")
		t.expect(#rules.check({ rule() }, member)).toBe(1) -- at its own hook (prepared) it refuses
		local reports = rules.memberReports({ rule() }, member)
		t.expect(#reports).toBe(1)
		t.expect(string.find(reports[1], ID, 1, true) ~= nil).toBe(true)
		-- a ready-hook rule of the raft itself still refuses
		local own = rule({ hook = "ready", presence = false })
		t.expect(#rules.check({ own }, view({ ["c0900.md"] = doc(ROW, "TODO later") }, "ready"))).toBe(1)
	end)

	it("every command calls rules.enforce for its hook", function()
		local main = fs.readFile(`{engine.TOP}/z-nile/engine/main.luau`)
		for _, hook in
			{
				"preparing",
				"prepared",
				"ready",
				"land",
				"done",
				"commit",
				"spend",
				"audit",
				"rewrite",
				"clean",
			}
		do
			t.expect(string.find(main, `rules.enforce("{hook}"`, 1, true) ~= nil).toBe(true)
		end
		-- ready and fold judge a member's prepared rules as reports: the member rules go through memberReports
		t.expect(string.find(main, "rules.memberReports(", 1, true) ~= nil).toBe(true)
		t.expect((string.find(main, 'rules.enforce("prepared", member', 1, true))).toBe(nil)
	end)

	it(
		"every registered rule passes its self-test and its module is named by its lesson, and the reverse",
		function()
			local tree = lessons.load(engine.TOP)
			t.expect(#registry > 0).toBe(true)
			local registered: { [string]: boolean } = {}
			for _, entry in registry do
				registered[entry.path] = true
				t.expect(rules.selfTest(entry.rule)).toEqual({})
				local l = lessons.parse(entry.rule.lesson, tree.lessons[entry.rule.lesson] or "")
				t.expect(l ~= nil).toBe(true)
				t.expect(table.find((l :: any).enforcedBy or {}, entry.path) ~= nil).toBe(true)
			end
			for id, text in tree.lessons do
				local l = lessons.parse(id, text)
				for _, ref in if l then (l :: any).enforcedBy or {} else {} do
					if string.find(ref, "z-nile/engine/rules/", 1, true) == 1 then
						t.expect(registered[ref]).toBe(true)
					end
				end
			end
		end
	)

	it("selfTest refuses a rule whose hook does not build a key it needs, or whose views lack it", function()
		local with = { capture = "the captured text" }
		local function carrying(extra: { [string]: any }): { [string]: any }
			return {
				needs = { "capture" },
				bad = {
					hook = "prepared",
					id = "c0900",
					files = { ["c0900.md"] = doc(ROW, "TODO later") },
					extra = extra,
				},
				good = {
					hook = "prepared",
					id = "c0900",
					files = { ["c0900.md"] = doc(ROW, "done") },
					extra = extra,
				},
			}
		end
		-- `prepared` builds `capture`, and the views carry it
		t.expect(rules.selfTest(rule(carrying(with)))).toEqual({})
		-- the views do not carry the key the rule declares
		local bare = rules.selfTest(rule(carrying({})))
		t.expect(#bare >= 1).toBe(true)
		t.expect(string.find(bare[1], "capture", 1, true) ~= nil).toBe(true)
		-- only `land` builds `subject`
		local lacks = carrying({ subject = "x" })
		lacks.needs = { "subject" }
		local problems = rules.selfTest(rule(lacks))
		t.expect(#problems >= 1).toBe(true)
		t.expect(string.find(problems[1], "subject", 1, true) ~= nil).toBe(true)
		-- a rule sees only the keys it declared: an undeclared read is nil, so its bad view is not flagged
		local sneaky = rule({
			needs = {},
			presence = false,
			check = function(v: rules.View): { string }
				return if v.extra and v.extra.capture then { "read an undeclared key" } else {}
			end,
			bad = { hook = "prepared", id = "c0900", files = {}, extra = { capture = "x" } },
			good = { hook = "prepared", id = "c0900", files = {} },
		})
		t.expect(#rules.selfTest(sneaky) >= 1).toBe(true)
		-- rules.check calls a rule with only its declared keys too, so production cannot read an undeclared one either
		t.expect(rules.check({ sneaky }, sneaky.bad)).toEqual({})
		local reporting = rule({
			needs = {},
			presence = false,
			report = true,
			check = sneaky.check,
			bad = sneaky.bad,
			good = sneaky.good,
		})
		t.expect(rules.reports({ reporting }, reporting.bad)).toEqual({})
	end)

	it(
		"the proof stamp round-trips, carries mutant kinds, check lines and a base, and goes stale on a spec byte or check.sh",
		function()
			local files = { ["acceptance/a.spec.luau"] = "return 1\n", ["check.sh"] = "check\n" }
			local info = {
				proto = "abc1234",
				base = "def5678",
				checks = { promoteCheck = "ok", lint = true },
				specs = { { file = "acceptance/a.spec.luau", pass = true } },
				mutants = { { n = 1, kind = "decider-first", case = "case one", killed = true } },
			}
			local stamp = prove.stamp(files, info)
			local text = prove.render(stamp)
			for _, line in
				{
					"spec-hash: ",
					"base: def5678",
					"promote-check: ok",
					"lint: ok",
					"mutant 1 decider-first: case one killed",
				}
			do
				t.expect(string.find(text, line, 1, true) ~= nil).toBe(true)
			end
			t.expect(prove.parse(text)).toEqual(stamp)
			t.expect(prove.fresh(stamp, files)).toBe(true)
			t.expect(
				prove.fresh(stamp, { ["acceptance/a.spec.luau"] = "return 2\n", ["check.sh"] = "check\n" })
			)
				.toBe(false)
			t.expect(
				prove.fresh(stamp, { ["acceptance/a.spec.luau"] = "return 1\n", ["check.sh"] = "check2\n" })
			)
				.toBe(false)
			local plus = {
				["acceptance/a.spec.luau"] = "return 1\n",
				["check.sh"] = "check\n",
				["design-review-001.md"] = "x",
			}
			t.expect(prove.fresh(stamp, plus)).toBe(true)
			t.expect(prove.parse("garbage")).toBe(nil)
			-- a prep whose specs require modules it will create: promote-check passes except for those requires
			local pending = prove.stamp(files, {
				proto = "abc1234",
				base = "def5678",
				checks = { promoteCheck = "pending", pending = 2, lint = true },
				specs = {},
				mutants = {},
			})
			local ptext = prove.render(pending)
			t.expect(string.find(ptext, "promote-check: pending 2", 1, true) ~= nil).toBe(true)
			t.expect(prove.parse(ptext)).toEqual(pending)
			t.expect(prove.acceptable(pending)).toBe(true) -- ok or pending, with lint ok
			t.expect(prove.acceptable(prove.stamp(files, {
				proto = "a",
				base = "b",
				checks = { promoteCheck = "fail", lint = true },
				specs = {},
				mutants = {},
			}))).toBe(false)
		end
	)

	it(
		"a stamp stays fresh through an id rewrite (restamp) and goes stale when the base moved under a Touched path",
		function()
			local files = { ["acceptance/a.spec.luau"] = "see c0100\n", ["check.sh"] = "check c0100\n" }
			local stamp = prove.stamp(
				files,
				{ proto = "abc1234", base = "def5678", checks = {}, specs = {}, mutants = {} }
			)
			local renamed = { ["acceptance/a.spec.luau"] = "see c0200\n", ["check.sh"] = "check c0200\n" }
			t.expect(prove.fresh(stamp, renamed)).toBe(false)
			local again = prove.restamp(stamp, renamed)
			t.expect(prove.fresh(again, renamed)).toBe(true)
			t.expect(again.base).toBe("def5678")
			-- the base moved: a change since it under a path the item touches makes the stamp stale; elsewhere it does not
			t.expect(prove.baseStale(stamp, { "z-nile/engine/x.luau" }, { "z-nile/engine" })).toBe(true)
			t.expect(prove.baseStale(stamp, { "pickman/src/x.luau" }, { "z-nile/engine" })).toBe(false)
		end
	)
end)
