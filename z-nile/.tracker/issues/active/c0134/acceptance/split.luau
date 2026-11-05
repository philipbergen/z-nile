--!strict
-- c0134: the one rule for which part of accept.spec.luau may change (design reviews 001 F1 and 002 F1). The header
-- is one contiguous run of plain line comments right after line 1: lines that are exactly `--` or start with `-- `
-- (never `--[` or `--!`, which can hide code or change the file's mode). Everything else is the body, byte for byte:
-- line 1, every line from the first that is not a plain comment, and the end of the file (a last line with no newline
-- is kept as it is). header.spec reads the header with it, and check.sh AC2 compares the bodies, so every byte of the
-- file is either in the header (which AC1 judges) or compared.
local split = {}

local function plainComment(line: string): boolean
	return line == "--" or string.sub(line, 1, 3) == "-- "
end

function split.cut(text: string): (string, string)
	local lines = string.split(text, "\n")
	local header: { string } = {}
	local i = 2
	while i <= #lines and i < #lines + (if lines[#lines] == "" then 0 else 1) and plainComment(lines[i]) do
		table.insert(header, lines[i])
		i += 1
	end
	local body: { string } = { lines[1] }
	for j = i, #lines do
		table.insert(body, lines[j])
	end
	return table.concat(header, "\n"), table.concat(body, "\n")
end

return split
