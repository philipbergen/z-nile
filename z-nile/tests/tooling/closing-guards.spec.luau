--!strict
-- R0115 review 001: the c0278 guards decide from texts and git results, never letting a gap through.
-- F1: a status-only edit or a move can't stamp a live document `closed-…` without being one exact close.
-- F2: a failed git read (grep, ls-tree, show) refuses instead of reading as "nothing found".
local closing = require("@znile/engine/closing")
local dispatch = require("@znile/engine/dispatch")
local publish = require("@znile/engine/publish")
local statusLib = require("@znile/engine/status")
local t = require("@tests/lib/t")

local LIVE = "---\nid: c0901\ntitle: T\nstatus: new\n---\n\n# c0901\n"
local function withStatus(value: string): string
	return (string.gsub(LIVE, "\nstatus: new\n", `\nstatus: {value}\n`, 1))
end
local function has(s: string?, needle: string): boolean
	return s ~= nil and string.find(s, needle, 1, true) ~= nil
end
local function run(ok: boolean, code: number, stdout: string): closing.Run
	return { ok = ok, code = code, stdout = stdout }
end

return t.spec("closing guards", function(it)
	it("F1: an existing document's status-only edit to closed-… without wont_do is refused", function()
		local why = publish.existingEdit("c0901", LIVE, withStatus("closed-quiet-copper-falcon"))
		t.expect(has(why, "may only edit its status: line (or be one close: ./zn close)")).toBe(true)
	end)

	it("F1: an exact close and a plain status edit of an existing document are accepted", function()
		local closed = closing.edit(LIVE, "moot", "closed-quiet-copper-falcon") :: string
		t.expect(publish.existingEdit("c0901", LIVE, closed)).toBe(nil)
		t.expect(publish.existingEdit("c0901", LIVE, withStatus("preparing-brisk-amber-otter"))).toBe(nil)
	end)

	it("F1: a closed existing document is never published again", function()
		local closed = closing.edit(LIVE, "moot", "closed-quiet-copper-falcon") :: string
		local why = publish.existingEdit("c0901", closed, withStatus("new-brisk-amber-otter"))
		t.expect(has(why, "c0901 is closed on origin/main")).toBe(true)
	end)

	it("F1: a move never produces a closed document, with or without wont_do", function()
		local stamped = withStatus("closed-quiet-copper-falcon")
		t.expect(has(publish.movedEdit("c0901", LIVE, stamped), "a move never closes an issue")).toBe(true)
		local full = closing.edit(LIVE, "moot", "closed-quiet-copper-falcon") :: string
		t.expect(has(publish.movedEdit("c0901", LIVE, full), "a move never closes an issue")).toBe(true)
		t.expect(publish.movedEdit("c0901", LIVE, withStatus("active-brisk-amber-otter"))).toBe(nil)
	end)

	-- R0115 final review 001 F1: the dispatcher's status comes from statusLib.effective over origin/main's document
	-- (main.luau cmd.dispatch's origin()); feed it a document as ./zn close writes it, not a hand-built "closed"
	it("final F1: close's document reaches dispatch.next as closed and stops it", function()
		local closed = closing.edit(LIVE, "moot", "closed-quiet-copper-falcon") :: string
		local front: { [string]: string } = {}
		local block = string.match(closed, "^%-%-%-\n(.-)\n%-%-%-") :: string
		for line in string.gmatch(block .. "\n", "([^\n]*)\n") do
			local k, v = string.match(line, "^([%w_]+):[ ]*(.*)$")
			if k and v then
				front[k] = v
			end
		end
		local facts: dispatch.Facts = {
			id = "c0901",
			folder = "pickman/.tracker/issues/c0901",
			root = "pickman/.tracker",
			kind = "issue",
			where = "backlog",
			status = statusLib.effective(front, "backlog"),
			design = front.design or "draft",
			raft = front.raft or "",
			ownClaim = false,
			localRaft = "",
			pr = nil,
			questions = false,
			openHuman = {},
			last = nil,
			uncovered = {},
			autoMerge = {},
			description = nil,
		}
		t.expect(facts.status).toBe("closed")
		local action = dispatch.next(facts)
		t.expect(action.kind).toBe("stop")
		t.expect(action.code).toBe(dispatch.EXIT.done)
	end)

	it("F2: git grep's no-match is no dependents, its failure refuses", function()
		local none, noErr = closing.grepHits(run(false, 1, ""))
		t.expect(#(none :: { string })).toBe(0)
		t.expect(noErr).toBe(nil)
		local hits = closing.grepHits(run(true, 0, "main:a/b.md\nmain:c/d.md\n")) :: { string }
		t.expect(#hits).toBe(2)
		local failed, err = closing.grepHits(run(false, 128, ""))
		t.expect(failed).toBe(nil)
		t.expect(has(err, "exit 128")).toBe(true)
	end)

	it("F2: a capture's added depends_on refuses when git can't read the dependency", function()
		local doc = "x/issues/c0902/c0902.md"
		local listFail = closing.addedDependency("p.md", "c0902", doc, run(false, 128, ""), nil)
		t.expect(has(listFail, "cannot list")).toBe(true)
		local showFail =
			closing.addedDependency("p.md", "c0902", doc, run(true, 0, "blob\n"), run(false, 128, ""))
		t.expect(has(showFail, "cannot read")).toBe(true)
		local absent = closing.addedDependency("p.md", "c0902", doc, run(true, 0, ""), nil)
		t.expect(absent).toBe(nil)
		local closed = closing.edit(LIVE, "moot", "closed-quiet-copper-falcon") :: string
		local refused =
			closing.addedDependency("p.md", "c0902", doc, run(true, 0, "blob\n"), run(true, 0, closed))
		t.expect(has(refused, "is closed (won't do)")).toBe(true)
		t.expect(closing.addedDependency("p.md", "c0902", doc, run(true, 0, "blob\n"), run(true, 0, LIVE)))
			.toBe(nil)
	end)
end)
