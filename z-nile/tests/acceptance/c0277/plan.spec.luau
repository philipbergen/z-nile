--!strict
-- c0277: the pure rules of a discarded worktree (z-nile/engine/heartbeat.luau): the numbered copy's name, the family a
-- lookup searches, which branch an `--item` may name, whether a worktree's claims may be taken over, the marker's text and
-- its one reader, when a discarded worktree is finished with and when it is kept anyway, and the discard fact a beat
-- loop stops on. No I/O, no clock.
local heartbeat = require("@znile/engine/heartbeat")
local t = require("@tests/lib/t")

local A = "preparing-quiet-copper-falcon"
local B = "preparing-sunny-heron-lynx"

local function verdict(id: string, stamp: string, kind: string, silent: number): heartbeat.Verdict
	return { id = id, state = "preparing", stamp = stamp, silent = silent, kind = kind }
end
local function facts(): heartbeat.DiscardFacts
	return {
		path = "/r/.worktree/prep-x",
		copy = "/r/.worktree/prep-x-1",
		branch = "prep-x-discarded-1",
		base = "prep-x",
		items = { "c0010" },
		since = 1800000000,
		pushedSha = "0123456789abcdef",
		pushed = { "aaa1111 pushed work" },
		unpushed = { "bbb2222 unpushed work" },
		dirty = { "?? pickman/dirty.txt" },
	}
end

return t.spec("c0277 discarded worktree rules", function(it)
	it("a discarded worktree's copy is named with the smallest free numeric suffix", function()
		t.expect(heartbeat.nextSuffix("R0010", {})).toBe("R0010-1")
		t.expect(heartbeat.nextSuffix("R0010", { "R0010", "R0010-1" })).toBe("R0010-2")
		t.expect(heartbeat.nextSuffix("R0010", { "R0010-1", "R0010-3" })).toBe("R0010-2") -- the smallest free
		t.expect(heartbeat.nextSuffix("prep-x", { "prep-xy-1" })).toBe("prep-x-1") -- another name's suffix is not ours
		t.expect(heartbeat.nextSuffix("prep-x", { "prep-x-01", "prep-x-1x", "prep-x-0" })).toBe("prep-x-1") -- digits only, from 1
	end)

	it(
		"the family is the name and its numbered copies; the current member is the highest one not discarded",
		function()
			t.expect(heartbeat.suffixOf("R0010", "R0010")).toBe(0)
			t.expect(heartbeat.suffixOf("R0010", "R0010-12")).toBe(12)
			t.expect(heartbeat.suffixOf("R0010", "R0010-x")).toBe(nil)
			t.expect(heartbeat.suffixOf("R0010", "R00100")).toBe(nil)
			t.expect(heartbeat.suffixOf("prep.x", "prep-x-1")).toBe(nil) -- a name is a name, not a pattern
			local names = { "prep-x", "prep-x-1", "prep-x-2" }
			t.expect(heartbeat.currentOf("prep-x", names, {})).toBe("prep-x-2")
			t.expect(heartbeat.currentOf("prep-x", names, { ["prep-x-2"] = true })).toBe("prep-x-1")
			t.expect(
				heartbeat.currentOf(
					"prep-x",
					names,
					{ ["prep-x"] = true, ["prep-x-1"] = true, ["prep-x-2"] = true }
				)
			).toBe(nil)
			t.expect(heartbeat.currentOf("prep-x", { "prep-xy" }, {})).toBe(nil)
		end
	)

	it("a worktree's base is the branch name it keeps; a raft layer's branch stands for its raft", function()
		t.expect(heartbeat.baseOf("prep-hello", "prep-hello-1")).toBe("prep-hello")
		t.expect(heartbeat.baseOf("R0010/2/c0020", "R0010-1")).toBe("R0010")
		t.expect(heartbeat.baseOf(nil, "R0010-3")).toBe("R0010")
		t.expect(heartbeat.baseOf(nil, "R0010")).toBe("R0010")
		t.expect(heartbeat.baseOf("R0010/2/c0020-discarded-1", "x")).toBe("R0010/2/c0020-discarded-1") -- not a layer
	end)

	it("a copy a taker is starting in is fresh until the limit", function()
		t.expect(heartbeat.fresh(1000, 1000, heartbeat.STALE)).toBe(true)
		t.expect(heartbeat.fresh(1000, 1000 + heartbeat.STALE - 1, heartbeat.STALE)).toBe(true)
		t.expect(heartbeat.fresh(1000, 1000 + heartbeat.STALE, heartbeat.STALE)).toBe(false)
		t.expect(heartbeat.fresh(nil, 1000, heartbeat.STALE)).toBe(false) -- no marker, or a damaged one
	end)

	it("--item is accepted only for the item's own branch", function()
		t.expect(heartbeat.ownsBranch("prep-hello", "c0010", "hello")).toBe(true)
		t.expect(heartbeat.ownsBranch("prep-plain", "c0010", "hello")).toBe(false)
		t.expect(heartbeat.ownsBranch("raft-hello", "R0010", "hello")).toBe(true)
		t.expect(heartbeat.ownsBranch("R0010/1/c0010", "c0010", "other")).toBe(true) -- the issue's own layer
		t.expect(heartbeat.ownsBranch("R0010/1/c0010", "R0010", "other")).toBe(true) -- a layer of the raft
		t.expect(heartbeat.ownsBranch("R0010/1/c0010", "c0020", "c0020")).toBe(false)
		t.expect(heartbeat.ownsBranch("main", "c0010", "main")).toBe(false)
		t.expect(heartbeat.ownsBranch(nil, "c0010", "hello")).toBe(false)
		t.expect(heartbeat.ownsBranch("", "c0010", "hello")).toBe(false)
	end)

	it("a worktree's claims may be taken over only when each is lost or already over", function()
		local lost = verdict("c0010", A, "lost", 4000)
		t.expect(heartbeat.discardRefusal({ { id = "c0010", remembered = A, current = A, verdict = lost } }))
			.toBe(nil)
		-- already over: origin shows another stamp (taken over elsewhere) or none (given back, merged)
		t.expect(heartbeat.discardRefusal({ { id = "c0010", remembered = A, current = B, verdict = nil } }))
			.toBe(nil)
		t.expect(heartbeat.discardRefusal({ { id = "c0010", remembered = A, current = nil, verdict = nil } }))
			.toBe(nil)
		-- a claim named by --item for a worktree that remembers none
		t.expect(heartbeat.discardRefusal({ { id = "c0010", remembered = "", current = A, verdict = lost } }))
			.toBe(nil)
		local reasons: { [string]: string } = {
			live = "claim alive",
			parked = "claim parked",
			nobeat = "never beaten",
			unknown = "no heartbeat verdict",
			stale = "no heartbeat verdict",
		}
		for kind, word in reasons do
			local why = heartbeat.discardRefusal({
				{ id = "c0010", remembered = A, current = A, verdict = verdict("c0010", A, kind, 60) },
			}, "pull requests unreadable: x")
			t.expect(why ~= nil and string.find(why, word, 1, true) ~= nil).toBe(true)
		end
		-- the verdict was judged for another stamp than origin holds now
		t.expect(heartbeat.discardRefusal({
			{ id = "c0010", remembered = A, current = A, verdict = verdict("c0010", B, "lost", 4000) },
		}) ~= nil).toBe(true)
		-- one live claim among lost ones refuses the whole worktree, naming it
		local mixed = heartbeat.discardRefusal({
			{ id = "c0010", remembered = A, current = A, verdict = lost },
			{ id = "c0020", remembered = B, current = B, verdict = verdict("c0020", B, "live", 60) },
		})
		t.expect(mixed ~= nil and string.sub(mixed, 1, 6) == "c0020:").toBe(true)
		-- no claim at all: name the item; a name that is no claim: nothing to take over
		local none = heartbeat.discardRefusal({})
		t.expect(none ~= nil and string.find(none, "--item", 1, true) ~= nil).toBe(true)
		local ghost =
			heartbeat.discardRefusal({ { id = "c0010", remembered = "", current = nil, verdict = nil } })
		t.expect(ghost ~= nil and string.find(ghost, "not a claim", 1, true) ~= nil).toBe(true)
	end)

	it("the marker names what happened and lists what was left, and one reader parses it", function()
		local text = heartbeat.discardText(facts())
		local d = heartbeat.discardParse(text)
		t.expect(d ~= nil).toBe(true)
		local got = d :: heartbeat.Discard
		t.expect(got.path).toBe("/r/.worktree/prep-x")
		t.expect(got.copy).toBe("/r/.worktree/prep-x-1")
		t.expect(got.branch).toBe("prep-x-discarded-1")
		t.expect(got.base).toBe("prep-x")
		t.expect(got.items).toEqual({ "c0010" })
		t.expect(got.since).toBe(1800000000)
		for _, needle in
			{
				"discarded worktree: /r/.worktree/prep-x",
				"this worktree was discarded: c0010's claim was taken over",
				"pick up something new",
				"pushed work",
				"unpushed work",
				"git -C /r/.worktree/prep-x-1 cherry-pick origin/prep-x..prep-x-discarded-1",
				"pickman/dirty.txt",
				"0123456",
			}
		do
			t.expect(string.find(text, needle, 1, true) ~= nil).toBe(true)
		end
		-- the refusal an old process reads is the body, and a damaged marker still refuses
		t.expect((string.find(heartbeat.discardedText(text), "discarded worktree: /r", 1, true))).toBe(nil)
		t.expect(string.find(heartbeat.discardedText(text), "was discarded", 1, true) ~= nil).toBe(true)
		t.expect(string.find(heartbeat.discardedText("junk"), "was discarded", 1, true) ~= nil).toBe(true)
		t.expect(heartbeat.discardParse("junk")).toBe(nil)
		t.expect(heartbeat.discardParse("discarded worktree: /x\n\nbody")).toBe(nil) -- a header with keys missing
	end)

	it(
		"a branch never pushed is cherry-picked from main, a long list is cut, and an empty note says so",
		function()
			local f = facts()
			f.pushedSha = ""
			f.pushed = {}
			local text = heartbeat.discardText(f)
			t.expect(string.find(text, "cherry-pick origin/main..prep-x-discarded-1", 1, true) ~= nil)
				.toBe(true)
			t.expect(string.find(text, "nothing was pushed", 1, true) ~= nil).toBe(true)
			local many: { string } = {}
			for i = 1, 25 do
				table.insert(many, `f{i}.txt`)
			end
			f.dirty = many
			local cut = heartbeat.discardText(f)
			t.expect(string.find(cut, "f20.txt", 1, true) ~= nil).toBe(true)
			t.expect((string.find(cut, "f21.txt", 1, true))).toBe(nil)
			t.expect(string.find(cut, "and 5 more", 1, true) ~= nil).toBe(true)
			local empty = heartbeat.discardText({
				path = "/p",
				copy = "/c",
				branch = "",
				base = "",
				items = { "R0010", "c0010" },
				since = 1,
				pushedSha = "",
				pushed = {},
				unpushed = {},
				dirty = {},
			})
			t.expect(string.find(empty, "nothing else was left here", 1, true) ~= nil).toBe(true)
			t.expect(string.find(empty, "R0010's claim was taken over (and 1 more)", 1, true) ~= nil)
				.toBe(true)
		end
	)

	it("a discarded worktree is finished with when none of its items is a live claim", function()
		t.expect(heartbeat.discardEnded({ c0010 = true }, { "c0010" })).toBe(false)
		t.expect(heartbeat.discardEnded({ c0010 = false }, { "c0010" })).toBe(true)
		t.expect(heartbeat.discardEnded({ R0010 = false, c0010 = true }, { "R0010", "c0010" })).toBe(false)
		t.expect(heartbeat.discardEnded({}, { "c0010" })).toBe(true) -- an item origin does not show is over
	end)

	it("a finished discarded worktree is kept while it holds work that exists nowhere else", function()
		t.expect(heartbeat.keepReason(0, 0)).toBe(nil)
		t.expect(heartbeat.keepReason(2, 0)).toBe("2 uncommitted file(s)")
		t.expect(heartbeat.keepReason(0, 3)).toBe("3 commit(s) exist nowhere else")
		t.expect(heartbeat.keepReason(1, 1)).toBe("1 uncommitted file(s) and 1 commit(s) exist nowhere else")
	end)

	it(
		"a beat loop has nowhere to beat from in a discarded worktree, after its session and its folder",
		function()
			t.expect(heartbeat.gone(nil, true, true, true))
				.toBe("its worktree was discarded (the claim was taken over)")
			t.expect(heartbeat.gone(nil, true, true, false)).toBe(nil)
			t.expect(heartbeat.gone(nil, true, true)).toBe(nil) -- c0275's three-argument form is unchanged
			t.expect(heartbeat.gone(false, true, true, true)).toBe("its session ended")
			t.expect(heartbeat.gone(nil, false, false, true)).toBe("its worktree is gone")
			t.expect(heartbeat.gone(nil, true, false, true))
				.toBe("its worktree was discarded (the claim was taken over)")
		end
	)
end)
