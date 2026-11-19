--!strict
-- f0417 AC7: what a claim may publish beside its status line: the marks `reviews: judged` (c0306) and `rounds: on`
-- (f0417), each only from absent, in any combination; nothing else (z-nile/engine/publish.luau, pure).
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")

local function doc(front: string): string
	return `---\nid: c0030\ntype: chore\ntitle: t\nslug: t\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-11-18\n{front}---\n\n# c0030\n\n## Problem\np\n`
end

local OLD = doc("status: new-quiet-copper-falcon\n")

return t.spec("f0417: the marks a claim may add", function(it)
	it("a claim may add rounds: on, reviews: judged, or both, beside its status line", function()
		t.expect(publish.claimMarks(OLD, doc("status: preparing-brisk-plucky-amber\nrounds: on\n"))).toBe(nil)
		t.expect(publish.claimMarks(OLD, doc("status: preparing-brisk-plucky-amber\nreviews: judged\n"))).toBe(nil)
		t.expect(publish.claimMarks(OLD, doc("status: preparing-brisk-plucky-amber\nreviews: judged\nrounds: on\n")))
			.toBe(nil)
		t.expect(publish.claimMarks(OLD, doc("status: preparing-brisk-plucky-amber\n"))).toBe(nil)
	end)

	it("a mark removed or changed, and any other key or body edit, are refused", function()
		local marked = doc("status: new-quiet-copper-falcon\nrounds: on\n")
		t.expect(publish.claimMarks(marked, doc("status: preparing-brisk-plucky-amber\n")) ~= nil).toBe(true)
		t.expect(publish.claimMarks(marked, doc("status: preparing-brisk-plucky-amber\nrounds: off\n")) ~= nil).toBe(true)
		t.expect(publish.claimMarks(OLD, doc("status: preparing-brisk-plucky-amber\nrounds: off\n")) ~= nil).toBe(true)
		t.expect(publish.claimMarks(OLD, doc("status: preparing-brisk-plucky-amber\nsize: 10\n")) ~= nil).toBe(true)
		local body = doc("status: preparing-brisk-plucky-amber\nrounds: on\n") .. "more\n"
		t.expect(publish.claimMarks(OLD, body) ~= nil).toBe(true)
	end)

	it("a claim may also add its one new-design-loop line under ## Loops, and no other line", function()
		local loop = "\n## Loops\n- Loop (tool, 2026-11-20): a new design loop from design-review-008\n"
		t.expect(publish.claimMarks(OLD, doc("status: preparing-brisk-plucky-amber\nrounds: on\n") .. loop)).toBe(nil)
		local more = "\n## Loops\n- Loop (tool, 2026-11-20): one more design round past design-review-008\n"
		t.expect(publish.claimMarks(OLD, doc("status: preparing-brisk-plucky-amber\nrounds: on\n") .. more) ~= nil).toBe(true)
		local two = loop .. "- Loop (tool, 2026-11-20): a new design loop from design-review-009\n"
		t.expect(publish.claimMarks(OLD, doc("status: preparing-brisk-plucky-amber\nrounds: on\n") .. two) ~= nil).toBe(true)
	end)
end)
