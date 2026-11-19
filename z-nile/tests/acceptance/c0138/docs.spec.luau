--!strict
-- c0138 AC3: the places that state when a compaction starts an item's new life say the same rule: the trail module's
-- header, the capture row of the zz-rules skill and the lesson item-history-spans-moves-and-compaction. Each says a
-- commit that changed the map and the document starts a life only when it renamed the item's id, and none keeps the
-- earlier wording ("changed the compaction map and its document" with nothing after it). Reads the real files; writes
-- nothing.
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

local RENAMED = "names the id on either side of a pair whose sides differ, or does not parse or can't be read"

return t.spec(
	"c0138 the rule for a compaction that starts a new life is stated alike everywhere",
	function(it)
		it(
			"the capture row says a life starts only at a commit that renamed the id, and a rewrite in place starts none",
			function()
				local doc = fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
				local row = string.match(doc, "\n| capture | [^\n]*") :: string
				t.expect(row ~= nil).toBe(true)
				t.expect(
					has(
						row,
						"when the item's life starts at a commit that changed the compaction map and its document and either renamed the item's id"
					)
				).toBe(true)
				t.expect(has(row, RENAMED)).toBe(true)
				t.expect(has(row, "or is where the item first appears")).toBe(true)
				t.expect(
					has(row, "a compaction that only rewrites a kept item's document in place starts no life")
				)
					.toBe(true)
				-- the row's other pinned words stay (c0119)
				t.expect(has(row, "`(history before <sha> not followed: it changed tracker/compaction.txt)`"))
					.toBe(true)
				t.expect(has(row, "no id change (a compaction or a `renumber`) is followed")).toBe(true)
				-- the earlier wording, which ended the sentence there, is gone
				t.expect(has(row, "that changed the compaction map and its document. A legacy")).toBe(false)
			end
		)

		it("the lesson says the walk stops only at a commit that renamed the id", function()
			local lesson = flat("z-nile/skills/zz-rules/lessons/item-history-spans-moves-and-compaction.md")
			t.expect(has(lesson, "together with the item's document and either renamed its id")).toBe(true)
			t.expect(has(lesson, RENAMED)).toBe(true)
			t.expect(has(lesson, "or is where the item first appears")).toBe(true)
			t.expect(
				has(lesson, "a compaction that only rewrites a kept item's document in place stops nothing")
			)
				.toBe(true)
			t.expect(has(lesson, "together with the item's document. Never walk")).toBe(false)
		end)

		it("the trail module's header says it too", function()
			local header = flat("z-nile/engine/trail.luau")
			t.expect(
				has(
					header,
					"also starts its life when the map as that commit leaves it names the item's id on either side of a pair whose sides differ (or does not parse or can't be read), or when the item first appears there"
				)
			).toBe(true)
			t.expect(has(header, "only rewrites its document in place")).toBe(true)
			-- the comment on `read`, the fifth place the rule is stated
			t.expect(has(header, "and renamed its id, or whose map does not parse or can't be read (`since`"))
				.toBe(true)
			t.expect(has(header, "starts nothing (c0138)")).toBe(true)
			t.expect(
				has(
					header,
					"pure over texts except `cuts`, `renames` and `read`, which run git and only read"
				)
			)
				.toBe(true)
			t.expect(has(header, "item's document also starts its life, and `read` returns a note"))
				.toBe(false)
		end)
	end
)
