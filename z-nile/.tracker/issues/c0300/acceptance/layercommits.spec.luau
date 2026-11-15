--!strict
-- c0300: the pure rules a restack keeps a layer by. Which copy of the layer branch holds every commit, a
-- commit's change as a text a clean rebase leaves alone, and whether a rebuilt layer kept one commit for each.
local layercommits = require("@znile/engine/layercommits")
local t = require("@tests/lib/t")

-- A copy that does not exist: a table literal cannot hold nil.
local NONE = {}

-- The two copies, as restack reads them; `over` sets the fields a case is about.
local function copies(over: { [string]: any }): layercommits.Copies
	local c: { [string]: any } = {
		localSha = "loc",
		remoteSha = "rem",
		remoteInLocal = false,
		localInRemote = false,
		sameCommits = false,
		localStacked = false,
		remoteStacked = false,
	}
	for k, v in over do
		c[k] = if v == NONE then nil else v
	end
	return (c :: any) :: layercommits.Copies
end

local function tipOf(over: { [string]: any }): string?
	return (layercommits.pickTip(copies(over)))
end

-- One file's section of a -U0 patch, as `git diff-tree -p -U0 --binary --full-index --no-renames --no-commit-id -r`
-- prints it.
local function section(path: string, index: string, hunk: string, lines: { string }): string
	local out = {
		`diff --git a/{path} b/{path}`,
		`index {index} 100644`,
		`--- a/{path}`,
		`+++ b/{path}`,
		hunk,
	}
	for _, line in lines do
		table.insert(out, line)
	end
	return table.concat(out, "\n")
end

local A1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
local A2 = "cccccccccccccccccccccccccccccccccccccccc..dddddddddddddddddddddddddddddddddddddddd"
local ONE = section("pickman/src/one.luau", A1, "@@ -10 +10 @@ local function a()", { "-old", "+new" })
local TWO = section("pickman/src/two.luau", A1, "@@ -3 +3 @@", { "-two", "+deux" })
local SPEND =
	section("pickman/.tracker/rafts/active/R0010/spend.md", A1, "@@ -3 +3 @@", { "-| a | 1 |", "+| b | 2 |" })

local function key(patch: string): string
	return layercommits.changeKey(patch, "R0010")
end

return t.spec("c0300: what a restack keeps of a layer", function(it)
	it(
		"AC2: the copy of the layer that holds every commit is picked, and diverged copies are refused",
		function()
			t.expect(tipOf({ localSha = "aaa", remoteSha = "aaa" })).toBe("aaa")
			t.expect(tipOf({ localSha = NONE, remoteSha = "bbb" })).toBe("bbb")
			t.expect(tipOf({ localSha = "aaa", remoteSha = NONE })).toBe("aaa")
			-- local is ahead of origin (an unpushed commit): local holds everything
			t.expect(tipOf({ remoteInLocal = true })).toBe("loc")
			-- local is behind origin (a stale clone): origin holds everything
			t.expect(tipOf({ localInRemote = true })).toBe("rem")
			-- neither is an ancestor and the commits differ: diverged
			local tip, why = layercommits.pickTip(copies({ sameCommits = false, localStacked = true }))
			t.expect(tip).toBe(nil)
			t.expect(string.find(why or "", "diverged", 1, true) ~= nil).toBe(true)
			local none, noTip = layercommits.pickTip(copies({ localSha = NONE, remoteSha = NONE }))
			t.expect(none).toBe(nil)
			t.expect(noTip ~= nil).toBe(true)
		end
	)

	it(
		"AC3: two copies holding the same commits on two bases are one layer: the one on the base, else local",
		function()
			-- a restack killed after moving the branch and before pushing: local is rebuilt on the base, origin is not
			t.expect(tipOf({ sameCommits = true, localStacked = true })).toBe("loc")
			-- a clone whose copy is the old one, after another clone restacked and pushed
			t.expect(tipOf({ sameCommits = true, remoteStacked = true })).toBe("rem")
			-- the base moved again since: either copy rebuilds the same layer; the local one is taken
			t.expect(tipOf({ sameCommits = true })).toBe("loc")
			t.expect(tipOf({ sameCommits = true, localStacked = true, remoteStacked = true })).toBe("loc")
		end
	)

	it(
		"AC1: a commit's change survives a clean rebase that moves its line numbers, blob ids and paths",
		function()
			local moved =
				section("pickman/src/one.luau", A2, "@@ -12 +12 @@ local function b()", { "-old", "+new" })
			t.expect(key(moved)).toBe(key(ONE))
			-- a rename on the new base: the same change under another path
			local renamed = section("pickman/src/uno.luau", A2, "@@ -10 +10 @@", { "-old", "+new" })
			t.expect(key(renamed)).toBe(key(ONE))
			-- a rename can reorder the sections
			t.expect(key(TWO .. "\n" .. ONE)).toBe(key(ONE .. "\n" .. TWO))
			-- a section missing is a different change
			t.expect(key(ONE) ~= key(ONE .. "\n" .. TWO)).toBe(true)
			-- an added or a removed line that differs is a different change
			local plus = section("pickman/src/one.luau", A1, "@@ -10 +10 @@", { "-old", "+newer" })
			t.expect(key(plus) ~= key(ONE)).toBe(true)
			local minus = section("pickman/src/one.luau", A1, "@@ -10 +10 @@", { "-older", "+new" })
			t.expect(key(minus) ~= key(ONE)).toBe(true)
			-- a removed Luau comment reads `--- …` in the patch: it is a change, not a header line
			local c1 = section("pickman/src/one.luau", A1, "@@ -10 +9,0 @@", { "--- one note" })
			local c2 = section("pickman/src/one.luau", A1, "@@ -10 +9,0 @@", { "--- another note" })
			t.expect(key(c1) ~= key(c2)).toBe(true)
			local p1 = section("pickman/src/one.luau", A1, "@@ -9,0 +10 @@", { "+++ one" })
			local p2 = section("pickman/src/one.luau", A1, "@@ -9,0 +10 @@", { "+++ two" })
			t.expect(key(p1) ~= key(p2)).toBe(true)
			-- a commit that became empty no longer carries its change
			t.expect(key("") ~= key(ONE)).toBe(true)
		end
	)

	it("AC1: the raft's derived spend.md is left out of a commit's change, and no other file is", function()
		t.expect(key(ONE .. "\n" .. SPEND)).toBe(key(ONE))
		-- git sorts the tracker path first: the files after it still count
		t.expect(key(SPEND .. "\n" .. ONE)).toBe(key(ONE))
		t.expect(key(SPEND .. "\n" .. ONE) ~= key(SPEND)).toBe(true)
		t.expect(key(SPEND .. "\n" .. ONE .. "\n" .. TWO)).toBe(key(ONE .. "\n" .. TWO))
		t.expect(key(SPEND)).toBe(key(""))
		-- another raft's spend.md is a change like any other
		t.expect(layercommits.changeKey(SPEND, "R0020") ~= layercommits.changeKey("", "R0020")).toBe(true)
	end)

	it(
		"AC2: a rebuilt layer must keep one commit per commit, with the same subject and change, in order",
		function()
			local held = {
				{ subject = "tracker: start R0010 Stack", change = "" },
				{ subject = "c0010: one", change = "+one" },
				{ subject = "c0010: two", change = "+two" },
			}
			t.expect(layercommits.keepsCommits(held, {
				{ subject = "tracker: start R0010 Stack", change = "" },
				{ subject = "c0010: one", change = "+one" },
				{ subject = "c0010: two", change = "+two" },
			})).toBe(nil)
			-- the truncation R0093 saw: only the last commit was rebuilt
			t.expect(layercommits.keepsCommits(held, { { subject = "c0010: two", change = "+two" } }) ~= nil)
				.toBe(true)
			-- a dropped middle commit
			local dropped = layercommits.keepsCommits(held, {
				{ subject = "tracker: start R0010 Stack", change = "" },
				{ subject = "c0010: two", change = "+two" },
			})
			t.expect(dropped ~= nil).toBe(true)
			-- a commit that became empty on the new base: it names the commit and says its change is already there
			local emptied = layercommits.keepsCommits(held, {
				{ subject = "tracker: start R0010 Stack", change = "" },
				{ subject = "c0010: one", change = "+one" },
				{ subject = "c0010: two", change = "" },
			})
			t.expect(string.find(emptied or "", '"c0010: two" is empty on the new base', 1, true) ~= nil)
				.toBe(true)
			-- a commit whose change is now another one
			local other = layercommits.keepsCommits(held, {
				{ subject = "tracker: start R0010 Stack", change = "" },
				{ subject = "c0010: one", change = "+one" },
				{ subject = "c0010: two", change = "+tw" },
			})
			t.expect(string.find(other or "", '"c0010: two" changes something else', 1, true) ~= nil)
				.toBe(true)
			-- the same commits in another order
			local swapped = layercommits.keepsCommits(held, {
				{ subject = "tracker: start R0010 Stack", change = "" },
				{ subject = "c0010: two", change = "+two" },
				{ subject = "c0010: one", change = "+one" },
			})
			t.expect(swapped ~= nil).toBe(true)
			-- the same change under another subject
			local reworded = layercommits.keepsCommits(held, {
				{ subject = "tracker: start R0010 Stack", change = "" },
				{ subject = "c0010: one, reworded", change = "+one" },
				{ subject = "c0010: two", change = "+two" },
			})
			t.expect(string.find(reworded or "", "c0010: one", 1, true) ~= nil).toBe(true)
			-- an extra commit
			local extra = layercommits.keepsCommits(held, {
				{ subject = "tracker: start R0010 Stack", change = "" },
				{ subject = "c0010: one", change = "+one" },
				{ subject = "c0010: two", change = "+two" },
				{ subject = "c0010: two", change = "+two" },
			})
			t.expect(extra ~= nil).toBe(true)
		end
	)
end)
