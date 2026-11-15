--!strict
-- c0278 AC1, AC2: the pure rules of closing an issue as won't do (z-nile/engine/closing.luau): the reason, the
-- refusals in their order, the edit, the readers of a closed document, the status vocabulary, and the publish guard
-- that accepts exactly a close.
local closing = require("@znile/engine/closing")
local status = require("@znile/engine/status")
local t = require("@tests/lib/t")

local STAMP = "closed-quiet-copper-falcon"

local function doc(statusLine: string, extra: string?): string
	return "---\nid: c0510\ntype: chore\ntitle: Mentions status: in its title\nslug: alpha\nraft: \n"
		.. "depends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-11-15\n"
		.. `status: {statusLine}\n{extra or ""}---\n\n# c0510\n\nstatus: a body line is not frontmatter\n`
end

local function facts(over: { [string]: any }?): closing.Facts
	local f: closing.Facts = {
		id = "c0510",
		kind = "issue",
		where = "backlog",
		status = "new",
		raft = "",
		dependents = {},
	}
	local g: any = f
	if over then
		for k, v in over do
			g[k] = v
		end
	end
	return f
end

local function has(s: string?, needle: string): boolean
	return s ~= nil and string.find(s, needle, 1, true) ~= nil
end

local function front(text: string): { [string]: string }
	local out: { [string]: string } = {}
	local block = string.match(text, "^%-%-%-\n(.-)\n%-%-%-") or ""
	for line in string.gmatch(block, "[^\n]+") do
		local k, v = string.match(line, "^([%w_]+):%s*(.-)%s*$")
		if k and v then
			out[k] = v
		end
	end
	return out
end

return t.spec("c0278 closing rules", function(it)
	it("checkReason refuses nil, empty, blank and multi-line reasons and takes one line", function()
		t.expect(has(closing.checkReason(nil), "--reason")).toBe(true)
		t.expect(has(closing.checkReason(""), "--reason")).toBe(true)
		t.expect(has(closing.checkReason("   \t "), "--reason")).toBe(true)
		t.expect(has(closing.checkReason("moot\nsecond line"), "one line")).toBe(true)
		t.expect(has(closing.checkReason("moot\r"), "one line")).toBe(true)
		t.expect(closing.checkReason("moot: c0264 rewrote the lines in place")).toBe(nil)
		t.expect(closing.checkReason("  padded  ")).toBe(nil)
	end)

	it(
		"refusal checks raft, none, done, active, closed, preparing, raft, dependents in that order",
		function()
			local raftId =
				closing.refusal(facts({ id = "R0510", kind = "raft", where = "none" }), "origin/main")
			t.expect(has(raftId, "R0510 is a raft: close takes an issue")).toBe(true)
			t.expect(has(raftId, "./zn unfold")).toBe(true)
			t.expect(closing.refusal(facts({ where = "none", status = "done" }), "origin/main"))
				.toBe("c0510 is not on origin/main")
			t.expect(closing.refusal(facts({ where = "none" }), "this tree"))
				.toBe("c0510 is not on this tree")
			local done =
				closing.refusal(facts({ where = "done", status = "done", raft = "R0510" }), "origin/main")
			t.expect(has(done, "c0510 is done")).toBe(true)
			local active =
				closing.refusal(facts({ where = "active", status = "active", raft = "R0510" }), "origin/main")
			t.expect(has(active, "readied (in active/)")).toBe(true)
			t.expect(has(active, "./zn stop R0510")).toBe(true)
			local closed =
				closing.refusal(facts({ status = "closed", raft = "R0510", dependents = { "c0520" } }), "x")
			t.expect(closed).toBe("c0510 is already closed")
			local preparing = closing.refusal(
				facts({ status = "preparing", raft = "R0510", dependents = { "c0520" } }),
				"origin/main"
			)
			t.expect(has(preparing, "being prepared (preparing on origin/main)")).toBe(true)
			t.expect(has(preparing, "./zn status c0510 new")).toBe(true)
			local rafted =
				closing.refusal(facts({ status = "prepared", raft = "R0510", dependents = { "c0520" } }), "x")
			t.expect(has(rafted, "c0510 is in R0510")).toBe(true)
			t.expect(has(rafted, "./zn unfold R0510 c0510")).toBe(true)
			local depended = closing.refusal(facts({ dependents = { "c0520", "f0530" } }), "origin/main")
			t.expect(has(depended, "named in the depends_on of c0520, f0530")).toBe(true)
			t.expect(has(depended, "drop it there first")).toBe(true)
		end
	)

	it("refusal takes new and raftless prepared", function()
		t.expect(closing.refusal(facts(), "origin/main")).toBe(nil)
		t.expect(closing.refusal(facts({ status = "prepared" }), "origin/main")).toBe(nil)
		t.expect(closing.refusal(facts({ status = "prepared" }), "this tree")).toBe(nil)
	end)

	it(
		"edit sets the stamp and appends wont_do as the last frontmatter key, keeping every other byte",
		function()
			local before = doc("new-amber-otter-lynx")
			local after = closing.edit(before, "moot: nothing to remove", STAMP)
			t.expect(after).toBe(doc(STAMP, "wont_do: moot: nothing to remove\n"))
			-- trimmed, and a document without frontmatter is not edited
			t.expect(closing.edit(before, "  moot  ", STAMP)).toBe(doc(STAMP, "wont_do: moot\n"))
			t.expect(closing.edit("# no frontmatter\n", "moot", STAMP)).toBe(nil)
			-- a document whose status: is derived (no line) gains one
			local bare = "---\nid: c0510\nslug: alpha\n---\n\n# c0510\n"
			t.expect(closing.edit(bare, "moot", STAMP))
				.toBe(`---\nid: c0510\nslug: alpha\nstatus: {STAMP}\nwont_do: moot\n---\n\n# c0510\n`)
		end
	)

	it("isClosed and reasonOf read the status and the trimmed wont_do", function()
		local closedText = closing.edit(doc("new-amber-otter-lynx"), "moot", STAMP) :: string
		t.expect(closing.isClosed(front(closedText))).toBe(true)
		t.expect(closing.reasonOf(front(closedText))).toBe("moot")
		t.expect(closing.isClosed(front(doc("new-amber-otter-lynx")))).toBe(false)
		t.expect(closing.isClosed({ status = "closed" })).toBe(true)
		t.expect(closing.isClosed({ status = "closedx-a-b-c" })).toBe(false)
		t.expect(closing.reasonOf({ wont_do = "   " })).toBe(nil)
		t.expect(closing.reasonOf({})).toBe(nil)
		t.expect(closing.KEY).toBe("wont_do")
	end)

	it("status parses a closed stamp and no move enters or leaves closed", function()
		t.expect(status.parse(STAMP)).toBe("closed")
		t.expect(status.parse("closed")).toBe("closed")
		t.expect(status.effective({ status = STAMP, design = "ready" }, "backlog")).toBe("closed")
		for _, other in { "new", "preparing", "prepared", "active", "done", "closed" } do
			t.expect(status.canMove("closed", other)).toBe(false)
			t.expect(status.canMove(other, "closed")).toBe(false)
		end
		-- the existing moves are kept
		t.expect(status.canMove("new", "preparing")).toBe(true)
		t.expect(status.canMove("preparing", "prepared")).toBe(true)
	end)

	it("guard accepts exactly a close", function()
		for _, from in { "new-amber-otter-lynx", "prepared-amber-otter-lynx" } do
			local before = doc(from)
			t.expect(closing.guard(before, closing.edit(before, "moot", STAMP) :: string)).toBe(nil)
		end
		local bare = "---\nid: c0510\nslug: alpha\n---\n\n# c0510\n"
		t.expect(closing.guard(bare, closing.edit(bare, "moot", STAMP) :: string)).toBe(nil)
	end)

	it(
		"guard refuses an extra edit, a second wont_do, an empty or multi-line reason, a non-closed stamp, a missing status change, and a document already closed or carrying wont_do",
		function()
			local before = doc("new-amber-otter-lynx")
			local good = closing.edit(before, "moot", STAMP) :: string
			local function refuses(after: string)
				local why = closing.guard(before, after)
				if why == nil or why == "" then
					error(`guard accepted:\n{after}`, 2)
				end
			end
			refuses(good .. "an extra body line\n")
			refuses((string.gsub(good, "title: Mentions", "title: Changed", 1)))
			refuses((string.gsub(good, "wont_do: moot\n", "wont_do: moot\nwont_do: again\n", 1)))
			refuses((string.gsub(good, "wont_do: moot\n", "wont_do: \n", 1)))
			refuses((string.gsub(good, "wont_do: moot\n", "wont_do:   \n", 1)))
			refuses((string.gsub(good, STAMP, "prepared-quiet-copper-falcon", 1)))
			refuses((string.gsub(good, STAMP, "closed", 1)))
			refuses((string.gsub(good, STAMP, "new-amber-otter-lynx", 1)))
			-- wont_do placed first rather than last
			refuses(
				(
					string.gsub(
						(string.gsub(good, "wont_do: moot\n", "", 1)),
						"^%-%-%-\n",
						"---\nwont_do: moot\n",
						1
					)
				)
			)
			-- a document already closed, or already carrying wont_do, is never closed again
			local closed = good
			t.expect(
				closing.guard(closed, closing.edit(closed, "again", "closed-brisk-amber-otter") :: string)
					~= nil
			).toBe(true)
			local carrying = doc("new-amber-otter-lynx", "wont_do: stray\n")
			local again = string.gsub(carrying, "new%-amber%-otter%-lynx", STAMP, 1)
			t.expect(closing.guard(carrying, again .. "") ~= nil).toBe(true)
			t.expect(closing.guard("# no frontmatter\n", good) ~= nil).toBe(true)
		end
	)

	it("closedDoc is true for a closed status or a wont_do line", function()
		t.expect(closing.closedDoc(closing.edit(doc("new-amber-otter-lynx"), "moot", STAMP) :: string))
			.toBe(true)
		t.expect(closing.closedDoc(doc(STAMP))).toBe(true)
		t.expect(closing.closedDoc(doc("new-amber-otter-lynx", "wont_do: stray\n"))).toBe(true)
		t.expect(closing.closedDoc(doc("new-amber-otter-lynx"))).toBe(false)
		t.expect(closing.closedDoc("# no frontmatter\n")).toBe(false)
	end)
end)
