--!strict
-- c0435: the easy path. An easy ticket with a short note and no design review is light (one rule, light.reason); a
-- review may say it is not easy (`Level:`), which the one rule reads as not light; raising is one way. Pure texts and
-- facts, plus lightready.check on an in-memory tree.
local contract = require("@znile/engine/contract")
local easy = require("@znile/engine/easy")
local light = require("@znile/engine/light")
local lightready = require("@znile/engine/lightready")
local readycheck = require("@znile/engine/readycheck")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local NOTE = table.concat({
	"### Short note",
	"- **Problem:** a three-line fix",
	"- **Change:** reject a bad id",
	"- **Files:** `z-nile/engine/ids.luau`",
	"- **Test:** `z-nile/tests/tooling/ids.spec.luau`",
	"- **Risk:** a good id refused",
}, "\n")

local function doc(extra: string?): string
	return "---\nid: c0001\nraft: \n---\n\n# c0001\n\n## Design\n"
		.. (extra or "")
		.. "\n\n## Regression guard\nOverrides: none\n"
end

local function member(risk: string?, text: string): light.Member
	return { risk = risk, doc = text, designReady = true }
end

return t.spec("c0435: the easy path", function(it)
	it("a complete short note is found and has no problem", function()
		local found, problem = easy.note(doc(NOTE))
		t.expect(found).toBe(true)
		t.expect(problem).toBe(nil)
	end)

	it("a document with no Short note heading has none: not found, no problem", function()
		local found, problem = easy.note(doc("just prose"))
		t.expect(found).toBe(false)
		t.expect(problem).toBe(nil)
	end)

	it("a note missing a part, with an empty part, or without a backticked path names the part", function()
		local noTest = string.gsub(NOTE, "\n%- %*%*Test:%*%*[^\n]*", "")
		local _, p1 = easy.note(doc(noTest))
		t.expect(has(p1, "Test")).toBe(true)
		local empty = string.gsub(NOTE, "reject a bad id", "")
		local _, p2 = easy.note(doc(empty))
		t.expect(has(p2, "Change")).toBe(true)
		local bare = string.gsub(NOTE, "`z%-nile/engine/ids.luau`", "ids")
		local _, p3 = easy.note(doc(bare))
		t.expect(has(p3, "Files")).toBe(true)
		local bareTest = string.gsub(NOTE, "`z%-nile/tests/tooling/ids.spec.luau`", "a spec")
		local _, p5 = easy.note(doc(bareTest))
		t.expect(has(p5, "Test")).toBe(true)
		local twice = NOTE .. "\n- **Change:** again"
		local _, p4 = easy.note(doc(twice))
		t.expect(has(p4, "Change")).toBe(true)
	end)

	it("a Short note heading at another level and plain Problem: lines work", function()
		local plain = string.gsub(string.gsub(NOTE, "### ", "#### "), "%*%*", "")
		local found, problem = easy.note(doc(plain))
		t.expect(found).toBe(true)
		t.expect(problem).toBe(nil)
	end)

	it("an easy ticket with the note and no design review is light", function()
		t.expect(light.reason({
			members = { member("easy", doc(NOTE)) },
			depsMet = true,
			designReviewed = false,
			reviews = {},
		})).toBe(nil)
	end)

	it("an easy ticket with no design review and no note, or a broken note, is not light", function()
		local none = light.reason({
			members = { member("easy", doc("prose")) },
			depsMet = true,
			designReviewed = false,
			reviews = {},
		})
		t.expect(has(none, "short note")).toBe(true)
		local broken = light.reason({
			members = { member("easy", doc(string.gsub(NOTE, "\n%- %*%*Risk:%*%*[^\n]*", ""))) },
			depsMet = true,
			designReviewed = false,
			reviews = {},
		})
		t.expect(has(broken, "Risk")).toBe(true)
	end)

	it(
		"an easy ticket with a design review needs no note (the old path is unchanged), and unjudged facts pass",
		function()
			t.expect(light.reason({
				members = { member("easy", doc("prose")) },
				depsMet = true,
				designReviewed = true,
				reviews = {},
			})).toBe(nil)
			t.expect(light.reason({ members = { member("easy", doc("prose")) }, depsMet = true })).toBe(nil)
		end
	)

	it("a normal or risky ticket is refused as before, note or not", function()
		for _, risk in { "normal", "risky" } do
			local why = light.reason({
				members = { member(risk, doc(NOTE)) },
				depsMet = true,
				designReviewed = false,
				reviews = {},
			})
			t.expect(has(why, `its risk is {risk}, not easy`)).toBe(true)
		end
		local why = light.reason({
			members = { member(nil, doc(NOTE)) },
			depsMet = true,
			designReviewed = false,
			reviews = {},
		})
		t.expect(has(why, "risk is normal")).toBe(true)
	end)

	it(
		"a review that says Level: normal or risky makes the ticket not light, from either kind of review",
		function()
			for _, level in { "normal", "risky" } do
				local why = light.reason({
					members = { member("easy", doc(NOTE)) },
					depsMet = true,
					designReviewed = false,
					reviews = { `# review\nVerdict: changes\nLevel: {level}\n` },
				})
				t.expect(has(why, "not easy")).toBe(true)
				t.expect(has(why, level)).toBe(true)
				t.expect(has(why, "z-design")).toBe(true)
			end
			-- a design review that raised it, then the ticket's own risk: edited back to easy: still not light
			local why = light.reason({
				members = { member("easy", doc("prose")) },
				depsMet = true,
				designReviewed = true,
				reviews = { "Verdict: approve\nLevel: normal\n" },
			})
			t.expect(has(why, "not easy")).toBe(true)
		end
	)

	it("easy.raised: the highest wins, easy and no line raise nothing, a bad value is a problem", function()
		t.expect((easy.raised({ "Level: normal\n", "Level: risky\n" }))).toBe("risky")
		t.expect((easy.raised({ "Level: risky\n", "Level: normal\n" }))).toBe("risky")
		t.expect((easy.raised({ "Level: easy\n", "Verdict: approve\n" }))).toBe(nil)
		t.expect((easy.raised({}))).toBe(nil)
		local level, problem = easy.raised({ "Level: hard\n" })
		t.expect(level).toBe(nil)
		t.expect(has(problem, "hard")).toBe(true)
		local viaLight = light.reason({
			members = { member("easy", doc(NOTE)) },
			depsMet = true,
			designReviewed = false,
			reviews = { "Level: hard\n" },
		})
		t.expect(has(viaLight, "hard")).toBe(true)
	end)

	it("easy.reviewTexts picks design-review and final-review files only", function()
		local got = easy.reviewTexts({
			["design-review-001.md"] = "a",
			["final-review-002.md"] = "b",
			["review-001.md"] = "c",
			["design-refute-001.md"] = "d",
			["c0001.md"] = "e",
		})
		table.sort(got)
		t.expect(got).toEqual({ "a", "b" })
		t.expect(easy.hasDesignReview({ ["design-review-001.md"] = "a" })).toBe(true)
		t.expect(easy.hasDesignReview({ ["final-review-001.md"] = "a", ["check.sh"] = "x" })).toBe(false)
	end)

	it("lightready.check: an easy ticket with the note, a check line and nothing else is taken", function()
		local function tree(body: string, extra: { [string]: string }?)
			local paths = { "z-nile/.tracker/issues/c0001/c0001.md", "z-nile/.tracker/issues/c0001/check.sh" }
			local files: { [string]: string } = {
				[paths[1]] = body,
				[paths[2]] = 'check "AC1: it works" true\n',
			}
			for p, text in extra or {} do
				table.insert(paths, p)
				files[p] = text
			end
			return paths, function(p: string): string?
				return files[p]
			end
		end
		local function front(risk: string): string
			return `---\nid: c0001\ntype: chore\nstatus: prepared-quiet-copper-falcon\nraft: \ndepends_on: []\ndesign: ready\nrisk: {risk}\n---\n\n# c0001\n\n## Design\n{NOTE}\n\n## Regression guard\nOverrides: none\n`
		end
		local paths, read = tree(front("easy"))
		t.expect(lightready.check("c0001", paths, read).why).toBe(nil)
		local p2, r2 = tree(front("normal"))
		t.expect(has(lightready.check("c0001", p2, r2).why, "not easy")).toBe(true)
		local noNote = string.gsub(front("easy"), "### Short note", "### Notes")
		local p3, r3 = tree(noNote)
		t.expect(has(lightready.check("c0001", p3, r3).why, "short note")).toBe(true)
		local p4, r4 = tree(noNote, {
			["z-nile/.tracker/issues/c0001/design-review-001.md"] = "Verdict: approve\n",
		})
		t.expect(lightready.check("c0001", p4, r4).why).toBe(nil)
		local p5, r5 = tree(front("easy"), {
			["z-nile/.tracker/issues/c0001/design-review-001.md"] = "Verdict: approve\nLevel: normal\n",
		})
		t.expect(has(lightready.check("c0001", p5, r5).why, "not easy")).toBe(true)
	end)

	it("the final review's text says it also judges the short note and may raise the level", function()
		local text = work.lightNote("R0001")
		t.expect(has(text, "short note")).toBe(true)
		t.expect(has(text, "Level:")).toBe(true)
	end)

	it("c0435 review 2 F2: every spelling of a Level line raises, and a Level line that is no level refuses", function()
		for _, form in {
			"Level: normal",
			"**Level:** normal",
			"- Level: normal",
			"  Level: normal",
			"Level : normal",
			"* **Level:** normal",
			"LEVEL: Normal",
			"Level: normal.",
		} do
			t.expect((easy.raised({ `# review\nVerdict: changes\n{form}\n` }))).toBe("normal")
			t.expect((easy.raised({ `# review\nVerdict: changes\n{form}` }))).toBe("normal") -- no newline at the end
		end
		t.expect((easy.raised({ "Level: risky" }))).toBe("risky")
		for _, bad in { "Levels: normal", "Level normal", "Level:", "level: **normal**x", "Level: hard" } do
			local level, problem = easy.raised({ `Verdict: approve\n{bad}\n` })
			t.expect(level).toBe(nil)
			t.expect(problem ~= nil).toBe(true)
		end
		t.expect((easy.raised({ "Verdict: approve\nthe level of care was fine\n" }))).toBe(nil)
	end)

	it("c0435 review 2 F3: the guard list holds the files that decide what is light, and a closer .models.toml", function()
		for _, path in {
			"z-nile/engine/easy.luau",
			"z-nile/engine/rounds.luau",
			"z-nile/engine/models.luau",
			"z-nile/engine/modelcmd.luau",
			"z-nile/.models.toml",
		} do
			t.expect(table.find(light.PROTECTED.files, path) ~= nil).toBe(true)
		end
		local _, why = light.judgeDiff("3\t1\tz-nile/.tracker/issues/c0001/.models.toml\n")
		t.expect(has(why, ".models.toml")).toBe(true)
		local _, again = light.judgeDiff("3\t1\tpickman/.models.toml\n")
		t.expect(has(again, ".models.toml")).toBe(true)
		local _, none = light.judgeDiff("3\t1\tz-nile/.tracker/issues/c0001/c0001.md\n")
		t.expect(none).toBe(nil)
	end)

	it("c0435 review 2 F4: ready refuses an easy member with no design review unless it is the light path", function()
		local doc = "---\nid: c0001\ndesign: ready\nrisk: easy\n---\n\n# c0001\n\n## Design\nD\n"
		local function raftOf(light: boolean?, reviewed: boolean): readycheck.Raft
			local m: readycheck.Member = {
				id = "c0001",
				design = "ready",
				doc = doc,
				deps = {},
				files = { ["c0001.md"] = doc, ["check.sh"] = 'check "AC1: holds" true\n' },
				specs = {},
				approval = nil,
				approvalFile = "z-nile/.tracker/issues/c0001/approval.md",
			}
			if reviewed then
				m.files["design-review-001.md"] = "Verdict: approve\n"
			end
			return {
				id = "R0001",
				where = "backlog",
				status = "prepared",
				dir = "z-nile/.tracker/rafts/R0001",
				design = "ready",
				doc = "---\ndesign: ready\n---\n",
				grouped = nil,
				questions = false,
				listed = { "c0001" },
				members = { m },
				files = { ["check.sh"] = 'check "RC0: ok" true\n' },
				loaded = true,
				light = light,
			}
		end
		t.expect(has(readycheck.reason(raftOf(nil, false)), "design review")).toBe(true)
		t.expect(readycheck.reason(raftOf(true, false))).toBe(nil)
		t.expect(readycheck.reason(raftOf(nil, true))).toBe(nil)
	end)

	it("c0435 review 2 F4: the walk sends an easy ticket that is not light and has no design review to draft", function()
		local base: work.IssueFact = {
			id = "c0001",
			root = "z-nile/.tracker",
			status = "prepared",
			raft = "",
			designReady = true,
			sized = true,
			deps = {},
			draftBlock = "",
			level = "easy",
			light = false,
			lightWhy = "a dependency has not landed",
			designReviewed = false,
		}
		local d = work.decide({ rafts = {}, issues = { base }, session = "s" })
		t.expect(d.action).toBe("draft")
		t.expect(has(d.why, "a dependency has not landed")).toBe(true)
		local reviewed = table.clone(base)
		reviewed.designReviewed = true
		local r = work.decide({ rafts = {}, issues = { reviewed }, session = "s" })
		t.expect(r.action ~= "draft").toBe(true)
	end)

	it("c0435 review 2 F5: risk: is part of the approval contract, only when it is not normal", function()
		local function docWith(risk: string?): string
			return `---\nid: c0001\n{if risk then `risk: {risk}\n` else ""}---\n\n## Problem\nP\n`
		end
		local function parts(risk: string?): contract.Parts
			return (contract.build(docWith(risk), "x\n", {})) :: contract.Parts
		end
		t.expect(contract.hash(parts(nil))).toBe(contract.hash(parts("normal")))
		t.expect(contract.hash(parts("easy")) ~= contract.hash(parts(nil))).toBe(true)
		t.expect(contract.hash(parts("risky")) ~= contract.hash(parts("easy"))).toBe(true)
		t.expect(parts("normal").risk).toBe(nil)
		t.expect(parts("easy").risk ~= nil).toBe(true)
	end)

	it("c0435 review 2 F7: the note counts only under Design, and its Test path must be in check.sh", function()
		local outside = "---\nid: c0001\n---\n\n## Problem\n" .. NOTE .. "\n\n## Design\nD\n"
		local found = easy.note(outside)
		t.expect(found).toBe(false)
		local check = 'check "AC1: ids" lune run tests/run -- z-nile/tests/tooling/ids.spec.luau\n'
		local f1, p1 = easy.note(doc(NOTE), check)
		t.expect(f1).toBe(true)
		t.expect(p1).toBe(nil)
		local _, p2 = easy.note(doc(NOTE), 'check "AC1: other" true\n')
		t.expect(has(p2, "check.sh")).toBe(true)
		local why = light.reason({
			members = { { risk = "easy", doc = doc(NOTE), designReady = true, check = 'check "AC1: o" true\n' } },
			depsMet = true,
			designReviewed = false,
			reviews = {},
		})
		t.expect(has(why, "check.sh")).toBe(true)
	end)
end)
