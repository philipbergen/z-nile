--!strict
-- c0435: the easy path. An easy ticket with a short note and no design review is light (one rule, light.reason); a
-- review may say it is not easy (`Level:`), which the one rule reads as not light; raising is one way. Pure texts and
-- facts, plus lightready.check on an in-memory tree.
local easy = require("@znile/engine/easy")
local light = require("@znile/engine/light")
local lightready = require("@znile/engine/lightready")
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
end)
