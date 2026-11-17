--!strict
-- The one rule for pinning a narrowed Luau spec whole (c0156): its text is normalised, then compared as a digest or a
-- golden string. The pin keeps every line break, blank lines included, and tolerates only:
--   * item ids such as f0130 (masked, so a compaction cannot break the pin),
--   * line endings (CRLF and a lone CR become LF),
--   * runs of spaces and tabs within a line (collapsed to one space; inside a string literal too, so a file with a
--     string holding a run of spaces or a tab keeps the exact-text pin) and trailing whitespace on a line,
--   * a comma before a closing brace, across at most one line break (stylua's table layout),
--   * the blank lines at the start and end of the text.
-- A vertical tab and a form feed stay as they are: a Luau comment runs through them, so they are neither a space nor a
-- line break (c0156 E9). A Luau `--` comment ends at its line, so a check joined onto the comment line above it is a
-- comment: the normalised text must change when a line break goes (R0045 code review 001 F1). Every reader of a pinned
-- file goes through `normalise` before it searches (code review 002 F1): `joined` and `without` do.
-- Pure over texts: the caller reads the file.
local serde = require("@lune/serde")

local pin = {}

function pin.normalise(text: string): string
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	text = string.gsub(text, "\r\n?", "\n")
	text = string.gsub(text, "[ \t]+", " ")
	text = string.gsub(text, " \n", "\n")
	text = string.gsub(text, ",( ?\n?[ ]?)}", "%1}")
	text = string.gsub(text, "^[%s]+", "")
	text = string.gsub(text, "[%s]+$", "")
	return text
end

-- the SHA-256 of the normalised text, as lowercase hex
function pin.digest(text: string): string
	return serde.hash("sha256", pin.normalise(text))
end

-- The mutant a careless edit makes: the normalised text with the line after the first line that ends in `comment`
-- joined onto it, the line break between them a space. Raises when no line ends in `comment` followed by a line break
-- (a comment on the last line has none), and when a blank line follows it: with nothing to join, a pin that "kills"
-- the result would prove nothing. Both texts go through `normalise`, so an id in the comment or the file's line
-- endings change nothing.
function pin.joined(text: string, comment: string): string
	local src = pin.normalise(text)
	local needle = pin.normalise(comment)
	local at = string.find(src, needle .. "\n", 1, true)
	if at == nil then
		error(`no line ends in the comment "{needle}"`, 2)
	end
	local cut = at + #needle
	local rest = string.sub(src, cut + 1)
	if string.sub(rest, 1, 1) == "\n" then
		error(`the comment "{needle}" is followed by a blank line: no line to join`, 2)
	end
	return string.sub(src, 1, cut - 1) .. " " .. (string.gsub(rest, "^ ", "", 1))
end

-- The other careless edit: the normalised text with the one occurrence of `piece` (normalised, so an assertion line may
-- be given with its indent and line ending) deleted. Raises when `piece` is empty, absent or occurs more than once, so
-- a pin that "kills" the result has deleted something certain.
function pin.without(text: string, piece: string): string
	local src = pin.normalise(text)
	local needle = pin.normalise(piece)
	local at, to = string.find(src, needle, 1, true)
	if needle == "" or at == nil or to == nil then
		error(`the text has no "{needle}" to delete`, 2)
	end
	if string.find(src, needle, to + 1, true) ~= nil then
		error(`"{needle}" occurs more than once in the text: nothing certain to delete`, 2)
	end
	return string.sub(src, 1, at - 1) .. string.sub(src, to + 1)
end

return pin
