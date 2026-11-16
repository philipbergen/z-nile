--!strict
-- c0322: the CLI's side of the rules bind-subject.spec.luau pins on the pure builders. `recordAndCommit` (the one
-- function behind `./zn commit` and `./zn done`'s binding commit) builds every row with one `ledger.commitRows` call
-- on the commit's own message, hands that call the session's reading as it is, builds no subject of its own, builds
-- the trailers with one `ledger.commitTrailers` call that takes the reading's note, and still prints the note. The
-- note is named three times in the function and nowhere else: the print, and the trailer call's argument. `./zn
-- finish` writes its own row, whose subject is the word finish and the note: not this issue's to change (Non-goals).
-- Reads engine/main.luau as text, from z-nile's home; comments do not count.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function count(text: string, needle: string): number
	local n, at = 0, 1
	while true do
		local from, to = string.find(text, needle, at, true)
		if not from then
			return n
		end
		n += 1
		at = (to :: number) + 1
	end
end
-- the code of the top-level function that starts at `head`, up to the next line that is exactly `end`, with comments
-- removed and every run of spaces, tabs and newlines made one space (so a reformat does not move a pin)
local function code(text: string, head: string): string
	local from = string.find(text, "\n" .. head, 1, true)
	if not from then
		error(`no function starts with "{head}"`, 2)
	end
	local to = string.find(text, "\nend\n", from, true)
	if not to then
		error(`"{head}" has no end`, 2)
	end
	-- a comment is two dashes and a space: `"--quiet"` in a git call is code
	local body = string.gsub(string.sub(text, from, to), "%-%- [^\n]*", "")
	return (string.gsub(body, "%s+", " "))
end

return t.spec("c0322 the CLI builds a commit's rows and trailers with the builders", function(it)
	it("one call builds the rows, from the commit's own message and the session's reading", function()
		local commit = code(fs.readFile("engine/main.luau"), "local function recordAndCommit(")
		t.expect(count(commit, "ledger.commitRows(")).toBe(1)
		-- the first argument is the message itself, never a text the note was folded into
		t.expect(has(commit, "ledger.commitRows( message, ")).toBe(true)
		-- the reading as the command got it: not a per-share copy, and not left out
		t.expect(has(commit, ' model, reading, if reading then sessionread.flags(reading) else "" )'))
			.toBe(true)
		t.expect(has(commit, "subject")).toBe(false) -- no subject is built, or added to, beside the builder
	end)

	it("the note is printed and handed to the trailers, and named nowhere else", function()
		local commit = code(fs.readFile("engine/main.luau"), "local function recordAndCommit(")
		t.expect(has(commit, "print(`session: {reading.note}`)")).toBe(true)
		t.expect(count(commit, "ledger.commitTrailers(")).toBe(1)
		t.expect(
			has(
				commit,
				"ledger.commitTrailers(phase :: string, kept, rows, if reading then reading.note else nil)"
			)
		).toBe(true)
		t.expect(count(commit, ".note")).toBe(2)
		-- the trailers that call returns are the ones the commit carries
		t.expect(
			has(commit, 'sh.git({ "commit", "--quiet", "-m", message, "-m", table.concat(trailers, "\\n") })')
		)
			.toBe(true)
	end)

	it("finish's own row is as it was: its subject is the word finish and the note", function()
		t.expect(has(fs.readFile("engine/main.luau"), "subject = `finish {reading.note}`,")).toBe(true)
	end)
end)
