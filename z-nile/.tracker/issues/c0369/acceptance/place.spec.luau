--!strict
-- c0369 AC1: where `./zn approve <id>` acts, decided by the pure `approveplace.choose` over the three worktrees
-- that are ever read (the one on prep-<slug>, the one the command runs in, the command's own) and origin/main.
local approveplace = require("@znile/engine/approveplace")
local t = require("@tests/lib/t")

local ID = "c0001"

local function copy(ready: boolean, state: string, hash: string?): approveplace.Copy
	return { ready = ready, slug = "hold", state = state, hash = hash }
end

-- kind: "prep" (on prep-hold), "here" (the checkout the command runs in), "scratch" (the command's own)
local function seen(kind: string, c: approveplace.Copy, base: string?): approveplace.Seen
	local name = if kind == "prep"
		then "prep-hold"
		elseif kind == "scratch" then ".approve-c0001"
		else "elsewhere"
	return {
		name = `.worktree/{name}`,
		path = `/repo/.worktree/{name}`,
		here = kind == "here",
		prep = kind == "prep",
		scratch = kind == "scratch",
		copy = c,
		base = base,
		landed = false,
		pushed = false,
	}
end

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

local MAIN: approveplace.Choice = { kind = "main", path = nil, name = "origin/main", record = true }
local APPROVED: approveplace.Choice = { kind = "approved", path = nil, name = "origin/main", record = false }
local PREP: approveplace.Choice =
	{ kind = "worktree", path = "/repo/.worktree/prep-hold", name = ".worktree/prep-hold", record = true }
-- the same place, to publish or push what it holds, with nothing new recorded
local HELD: approveplace.Choice =
	{ kind = "worktree", path = "/repo/.worktree/prep-hold", name = ".worktree/prep-hold", record = false }

return t.spec("c0369 the place an approval is recorded in", function(it)
	it("takes the prep worktree whose design is its own and has no matching approval", function()
		-- a redesign while main holds the approved older design
		local main = copy(true, "holds", "old")
		t.expect(approveplace.choose(ID, main, { seen("prep", copy(true, "changed", "new"), "old") }, false))
			.toEqual(PREP)
		-- a first design: main holds a draft, or nothing
		local draft = copy(false, "none", "draft")
		t.expect(approveplace.choose(ID, draft, { seen("prep", copy(true, "none", "new"), "draft") }, false))
			.toEqual(PREP)
		t.expect(approveplace.choose(ID, nil, { seen("prep", copy(true, "none", "new"), nil) }, false))
			.toEqual(PREP)
		-- an approval file that does not parse still sends the command there, where it is refused by name
		t.expect(approveplace.choose(ID, main, { seen("prep", copy(true, "bad", "new"), "old") }, false))
			.toEqual(PREP)
	end)

	it("does not take a worktree that only holds a design main has or had", function()
		local main = copy(true, "none", "now")
		local behind: { approveplace.Seen } = {
			seen("prep", copy(true, "none", "now"), "before"), -- main's own design
			seen("prep", copy(true, "none", "before"), "before"), -- only behind main
			seen("here", copy(true, "none", "before"), "before"),
			seen("prep", copy(false, "none", "other"), "before"), -- a draft
			seen("prep", copy(true, "none", nil), "before"), -- a contract that cannot be built
		}
		for _, w in behind do
			t.expect(approveplace.choose(ID, main, { w }, false)).toEqual(MAIN)
		end
		-- a prep whose pull request merged, after which main moved on
		local merged = seen("prep", copy(true, "none", "earlier"), "draft")
		merged.landed = true
		t.expect(approveplace.choose(ID, main, { merged }, false)).toEqual(MAIN)
		merged.landed = false
		t.expect(approveplace.choose(ID, main, { merged }, false)).toEqual(PREP)
	end)

	it(
		"prefers a worktree's own design to origin/main's, and the worktree the command runs in to the prep",
		function()
			local main = copy(true, "none", "now")
			local prep = seen("prep", copy(true, "none", "newer"), "now")
			t.expect(approveplace.choose(ID, main, { prep }, false)).toEqual(PREP)
			local here = seen("here", copy(true, "none", "mine"), "now")
			local inside = approveplace.choose(ID, main, { prep, here }, false)
			t.expect(inside and inside.name).toBe(".worktree/elsewhere")
			local swapped = approveplace.choose(ID, main, { here, prep }, false)
			t.expect(swapped and swapped.name).toBe(".worktree/elsewhere")
		end
	)

	it(
		"says an approved design is approved, and refuses when nothing is ready, without sending the person anywhere",
		function()
			t.expect(approveplace.choose(ID, copy(true, "holds", "now"), {}, false)).toEqual(APPROVED)
			local _, draft = approveplace.choose(ID, copy(false, "none", "now"), {}, false)
			t.expect(has(draft, "c0001: nothing to approve: it is not design: ready on origin/main"))
				.toBe(true)
			t.expect(has(draft, "prep-hold")).toBe(true)
			local _, absent =
				approveplace.choose(ID, nil, { seen("prep", copy(false, "none", "x"), nil) }, false)
			t.expect(has(absent, "c0001: nothing to approve: it is not on origin/main")).toBe(true)
			local refusals: { string? } = { draft, absent }
			for _, refusal in refusals do
				t.expect(has(refusal, "inside")).toBe(false)
				t.expect(has(refusal, "cd ")).toBe(false)
			end
		end
	)

	it(
		"publishes an approval already recorded for the design main holds, and never records it twice",
		function()
			-- the prep merged before the person approved; the approval sits in the prep worktree, or in the command's own
			local main = copy(true, "none", "now")
			local kinds = { "prep", "scratch", "here" }
			local modes = { false, true }
			for _, kind in kinds do
				local held = seen(kind, copy(true, "holds", "now"), "before")
				for _, publishOnly in modes do
					local choice = approveplace.choose(ID, main, { held }, publishOnly)
					t.expect(choice and choice.kind).toBe("worktree")
					t.expect(choice and choice.path).toBe(held.path)
					t.expect(choice and choice.record).toBe(false)
				end
			end
			-- main's approval of that design already holds: there is nothing to publish
			local done = copy(true, "holds", "now")
			for _, publishOnly in modes do
				t.expect(
					approveplace.choose(
						ID,
						done,
						{ seen("prep", copy(true, "holds", "now"), "before") },
						publishOnly
					)
				).toEqual(APPROVED)
			end
		end
	)

	it(
		"never retries a record of a design that is nobody's: a leftover of a failed publish, a merged prep",
		function()
			local main = copy(true, "holds", "new")
			-- the command's own worktree, left by a failed publish of the design main has since replaced
			local leftover = seen("scratch", copy(true, "holds", "old"), "old")
			local stale = seen("prep", copy(true, "holds", "older"), "draft")
			stale.landed = true
			local modes = { false, true }
			for _, publishOnly in modes do
				t.expect(approveplace.choose(ID, main, { leftover, stale }, publishOnly)).toEqual(APPROVED)
			end
			-- and while main's new design waits, the plain command approves main's, the retry has nothing
			local waiting = copy(true, "changed", "new")
			t.expect(approveplace.choose(ID, waiting, { leftover, stale }, false)).toEqual(MAIN)
			local _, none = approveplace.choose(ID, waiting, { leftover, stale }, true)
			t.expect(has(none, "c0001 has no recorded approval to publish. Run ./zn approve c0001."))
				.toBe(true)
		end
	)

	it("retries an unpushed approval of a prep's own design, and leaves a pushed one alone", function()
		local main = copy(false, "none", "draft")
		local prep = seen("prep", copy(true, "holds", "newer"), "draft")
		local modes = { false, true }
		for _, publishOnly in modes do
			t.expect(approveplace.choose(ID, main, { prep }, publishOnly)).toEqual(HELD)
		end
		prep.pushed = true
		for _, publishOnly in modes do
			t.expect(approveplace.choose(ID, main, { prep }, publishOnly))
				.toEqual({ kind = "pushed", path = nil, name = ".worktree/prep-hold", record = false })
		end
		-- --publish never records: a prep that still waits for its approval is not its business
		local unapproved = seen("prep", copy(true, "none", "newer"), "draft")
		local _, none = approveplace.choose(ID, main, { unapproved }, true)
		t.expect(has(none, "c0001 has no recorded approval to publish")).toBe(true)
		-- an unpushed record comes before a new approval of main's own design
		local ready = copy(true, "none", "now")
		prep.pushed = false
		prep.base = "now"
		t.expect(approveplace.choose(ID, ready, { prep }, false)).toEqual(HELD)
	end)

	it(
		"never approves main's older design behind a prep's own pushed design, asked again or retried",
		function()
			local pushed: approveplace.Choice =
				{ kind = "pushed", path = nil, name = ".worktree/prep-hold", record = false }
			local modes = { false, true }
			-- main holds an older design, ready and unapproved, or one whose approval holds
			for _, main in
				{ copy(true, "none", "old"), copy(true, "changed", "old"), copy(true, "holds", "old") }
			do
				local prep = seen("prep", copy(true, "holds", "new"), "old")
				prep.pushed = true
				for _, publishOnly in modes do
					t.expect(approveplace.choose(ID, main, { prep }, publishOnly)).toEqual(pushed)
				end
			end
		end
	)
end)
