--!strict
-- c0226 AC3: the places that restate which commits are compactions say a move that changes the map is one: the trail
-- module's header, history's header comment and the lesson item-history-spans-moves-and-compaction, and none keeps the
-- claim that `trail.cuts` reads the map "with renames". Reads the real files; writes nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
-- specs run from their project's home; the repository's files live at the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string, phrase: string): boolean
	return string.find(text, phrase, 1, true) ~= nil
end
-- the whole text with its line breaks (and the comment marks after them) folded into single spaces, so a sentence a
-- comment wraps is still one sentence
local function flat(path: string): string
	local text = fs.readFile(`{TOP}/{path}`)
	return (string.gsub(string.gsub(text, "\n%-%-%s*", " "), "\n", " "))
end

return t.spec("c0226 the compaction rule is restated alike", function(it)
	it(
		"AC3: the trail module's header says moving the map and changing it in one commit is a compaction",
		function()
			local header = flat("z-nile/engine/trail.luau")
			t.expect(
				has(
					header,
					"Moving the map unchanged (c0114) is not a compaction; moving and changing it in the same commit is one"
				)
			).toBe(true)
			t.expect(has(header, "Moving the map (c0114) is not a compaction.")).toBe(false)
		end
	)

	it(
		"AC3: history's header comment says it too, and no longer says trail.cuts reads it with renames",
		function()
			local hist = flat("z-nile/engine/history.luau")
			t.expect(
				has(hist, "moving the map unchanged is none, moving and changing it in one commit is one")
			)
				.toBe(true)
			t.expect(has(hist, "trail.cuts reads it the same way, with renames")).toBe(false)
		end
	)

	it(
		"AC3: the lesson names the one rule and no longer says trail.cuts reads the map with renames",
		function()
			local lesson = flat("z-nile/skills/zz-rules/lessons/item-history-spans-moves-and-compaction.md")
			t.expect(has(lesson, "a `git mv` that also changes the map's content is one")).toBe(true)
			t.expect(has(lesson, "`ids.cutFile`")).toBe(true)
			t.expect(has(lesson, "`trail.cuts` reads it with renames")).toBe(false)
		end
	)
end)
