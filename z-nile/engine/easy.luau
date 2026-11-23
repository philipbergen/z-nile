--!strict
-- c0435: the easy path's two small readers. An easy ticket may skip its separate design review when its design is a
-- short note, and the one review that remains (the final review) may say the ticket is not easy. Pure: texts in,
-- answers out. The one rule that uses them is light.reason; the readers are lightready, lightgit and workread.

local easy = {}

easy.PARTS = { "Problem", "Change", "Files", "Test", "Risk" } :: { string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- The value of a `Part:` line (list marker and `**` emphasis allowed), or nil when the line is not one.
local function part(line: string): (string?, string?)
	local plain = trim(line)
	plain = string.gsub(plain, "^[-*+]%s+", "")
	plain = string.gsub(plain, "%*%*", "")
	local name, value = string.match(plain, "^(%a+)%s*:%s*(.-)%s*$")
	if name and table.find(easy.PARTS, name) then
		return name, value
	end
	return nil, nil
end

-- The short note of a ticket document: (found, problem). Found when a heading titled `Short note` (any level) exists;
-- the problem names the first part that is missing, empty or given twice, or a Files or Test line with no backticked
-- token. A document with no such heading is simply not short: (false, nil).
function easy.note(doc: string): (boolean, string?)
	local level = 0
	local seen: { [string]: string } = {}
	local problem: string? = nil
	local found = false
	local fenced = false
	for line in string.gmatch(doc .. "\n", "([^\n]*)\n") do
		if string.match(line, "^%s*```") or string.match(line, "^%s*~~~") then
			fenced = not fenced
		end
		local hashes, title = string.match(line, "^(#+)%s+(.-)%s*$")
		if not fenced and hashes then
			if level == 0 and string.lower(title or "") == "short note" then
				level = #hashes
				found = true
			elseif level > 0 and #hashes <= level then
				break
			end
		elseif level > 0 and not fenced then
			local name, value = part(line)
			if name and value then
				if seen[name] ~= nil and problem == nil then
					problem = `the short note gives {name}: twice`
				end
				seen[name] = value
			end
		end
	end
	if not found then
		return false, nil
	end
	if problem then
		return true, problem
	end
	for _, name in easy.PARTS do
		local value = seen[name]
		if value == nil or value == "" then
			return true, `the short note has no {name}: (it needs Problem, Change, Files, Test and Risk)`
		end
		if (name == "Files" or name == "Test") and not string.find(value, "`[^`]+`") then
			return true, `the short note's {name}: names nothing in backticks`
		end
	end
	return true, nil
end

local RANK = { normal = 1, risky = 2 } :: { [string]: number }

-- The level the reviews raised the ticket to: a `Level:` line in any review text. The highest of normal and risky
-- wins; `Level: easy` and no line raise nothing; any other value is a problem (fail closed).
function easy.raised(reviews: { string }): (string?, string?)
	local best: string? = nil
	for _, text in reviews do
		for value in string.gmatch("\n" .. text, "\n[Ll]evel:[ \t]*([^\n]-)[ \t]*\n") do
			local word = string.lower(value)
			if word ~= "easy" then
				if RANK[word] == nil then
					return nil, `a review has Level: {value}, which is not easy, normal or risky`
				end
				if best == nil or RANK[word] > RANK[best :: string] then
					best = word
				end
			end
		end
	end
	return best, nil
end

local function isReview(name: string): boolean
	return string.match(name, "^design%-review%-%d+%.md$") ~= nil
		or string.match(name, "^final%-review%-%d+%.md$") ~= nil
end

-- The texts of the design-review and final-review files in a name -> text map (a folder's files).
function easy.reviewTexts(files: { [string]: string }): { string }
	local out: { string } = {}
	for name, text in files do
		if isReview(name) then
			table.insert(out, text)
		end
	end
	return out
end

-- Whether a name -> text map holds a design review round.
function easy.hasDesignReview(files: { [string]: string }): boolean
	for name in files do
		if string.match(name, "^design%-review%-%d+%.md$") then
			return true
		end
	end
	return false
end

return easy
