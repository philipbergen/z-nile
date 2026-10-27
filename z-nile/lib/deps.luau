--!strict
-- The one reader of an architecture document's ```deps block (c0163): the declared dependencies between features,
-- one `Consumer -> Provider` edge per line. It fails closed: a line that is neither an edge, a blank line nor a
-- `#` comment is a problem naming its line in the document, never skipped, so a conflict marker or a stray word in
-- the block fails the spec that reads it. So is a document with no deps block or with two.
local deps = {}

export type Graph = { [string]: { [string]: boolean } }

-- The edges of `md`'s deps block, and the problems (empty when the block read cleanly). `name` labels the problems.
function deps.parse(md: string, name: string): (Graph, { string })
	local graph: Graph = {}
	local problems: { string } = {}
	local n = 0
	local inside = false
	local blocks = 0
	for line in string.gmatch(md .. "\n", "([^\n]*)\n") do
		n += 1
		local l = if string.sub(line, -1) == "\r" then string.sub(line, 1, -2) else line
		if not inside then
			if l == "```deps" then
				inside = true
				blocks += 1
			end
		elseif string.match(l, "^```%s*$") then
			inside = false
		elseif not (string.match(l, "^%s*$") or string.match(l, "^%s*#")) then -- blank lines and comments pass
			local consumer, provider = string.match(l, "^%s*(%w+)%s*%->%s*(%w+)%s*$")
			if consumer and provider then
				local set = graph[consumer] or {}
				set[provider] = true
				graph[consumer] = set
			else
				table.insert(
					problems,
					`{name}:{n}: "{l}" in the deps block is not an edge (A -> B), a blank line or a # comment`
				)
			end
		end
	end
	if blocks == 0 then
		table.insert(problems, `{name}: no deps block`)
	elseif blocks > 1 then
		table.insert(problems, `{name}: {blocks} deps blocks; one is the declared graph`)
	end
	if inside then
		table.insert(problems, `{name}: the deps block is never closed`)
	end
	return graph, problems
end

return deps
