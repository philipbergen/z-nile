--!strict
-- c0134: the one boundary reader for accept.spec.luau's header and body (design review 001 F1): line 1 (`--!strict`)
-- is neither; the header is the block of comment lines right after it; the body is everything from the first line
-- after line 1 that is not a comment. header.spec and check.sh AC2 (through body.luau) both cut here, so a line
-- inserted at the boundary is either in the header or in the body, never in neither.
local split = {}

function split.cut(text: string): (string, string)
	local header: { string } = {}
	local body: { string } = {}
	local n = 0
	local inBody = false
	for line in string.gmatch(text, "([^\n]*)\n") do
		n += 1
		if n > 1 then
			if not inBody and string.sub(line, 1, 2) == "--" then
				table.insert(header, line)
			else
				inBody = true
				table.insert(body, line)
			end
		end
	end
	return table.concat(header, "\n"), table.concat(body, "\n")
end

return split
