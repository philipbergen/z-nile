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
function easy.note(doc: string, check: string?): (boolean, string?)
	local level = 0
	local inDesign = false
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
			if #hashes == 2 then
				inDesign = string.lower(title or "") == "design"
			end
			if level == 0 and inDesign and #hashes > 2 and string.lower(title or "") == "short note" then
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
	local token = string.match(seen.Test :: string, "`([^`]+)`") :: string
	if string.sub(token, -10) ~= ".spec.luau" then
		return true, `the short note's Test: {token} is not a spec file (a path ending in .spec.luau)`
	end
	if check ~= nil and string.find(check, 'check "', 1, true) then -- no check line: readycheck says so
		local runs = false
		for line in string.gmatch(check .. "\n", "([^\n]*)\n") do
			if string.match(line, '^%s*check%s+"') and easy.runsPath(line, token) then
				runs = true
			end
		end
		if not runs then
			return true,
				`the short note's Test: {token} is not run by a check line of the ticket's check.sh (its AC1 line must run it)`
		end
	end
	if not easy.hasAc1(doc) then
		return true, "the ticket has no AC1 line under ## Acceptance criteria (its AC1 is the note's Test:)"
	end
	return true, nil
end

-- Whether a check line runs `path`: the path stands as a word of the command (after a space, a quote, `=` or `/`, before
-- a space, a quote or the end), not in a trailing `# comment`.
function easy.runsPath(line: string, path: string): boolean
	local command = string.match(line, "^(.-)%s+#") or line
	for at = 1, #command - #path + 1 do
		if string.sub(command, at, at + #path - 1) == path then
			local before = if at == 1 then " " else string.sub(command, at - 1, at - 1)
			local after = string.sub(command, at + #path, at + #path)
			if
				string.find(" \t\"'=/", before, 1, true)
				and (after == "" or string.find(" \t\"'", after, 1, true))
			then
				return true
			end
		end
	end
	return false
end

-- Whether the ticket's `## Acceptance criteria` section holds an AC1 line (the trace needs one).
function easy.hasAc1(doc: string): boolean
	local inside = false
	for line in string.gmatch(doc .. "\n", "([^\n]*)\n") do
		local hashes, title = string.match(line, "^(#+)%s+(.-)%s*$")
		if hashes and #hashes == 2 then
			inside = string.lower(title or "") == "acceptance criteria"
		elseif inside and string.match(line, "^%s*[-*+%d.%s]*%**AC1%f[%W]") then
			return true
		end
	end
	return false
end

local RANK = { normal = 1, risky = 2 } :: { [string]: number }

-- One line of a review as a candidate Level line: leading heading marks, quote marks, list markers (`-`, `*`, `N.`),
-- backticks and `**`/`__` emphasis stripped, lower-cased. Returns the text after `level:`, or nil when the line is not one.
local function levelValue(line: string): string?
	local plain = trim(line)
	-- every pass that changes the line removes at least one character, so the line's length bounds the passes
	for _ = 1, #plain + 1 do
		local before = plain
		plain = trim((string.gsub(plain, "^#+%s*", "", 1)))
		plain = trim((string.gsub(plain, "^>%s*", "", 1)))
		plain = trim((string.gsub(plain, "^[-*+]%s+", "", 1)))
		plain = trim((string.gsub(plain, "^%d+[.)]%s+", "", 1)))
		if plain == before then
			break
		end
	end
	plain = string.lower((string.gsub(string.gsub(string.gsub(plain, "%*%*", ""), "__", ""), "`", "")))
	return string.match(plain, "^level%s*:%s*(.-)%s*$")
end

-- The level the reviews raised the ticket to, and a problem when a Level line holds no level. A line is a candidate only
-- when it is `Level:` after its markers are stripped (so `Level 2 ghosts...` prose is not); lines in fenced code blocks
-- are skipped; the first word after the colon is the value and the rest of the line is ignored. The highest of normal
-- and risky wins; `Level: easy` and no line raise nothing. Callers refuse on a problem, never fall through.
function easy.raised(reviews: { string }): (string?, string?)
	local best: string? = nil
	for _, text in reviews do
		local fenced = false
		for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
			if string.match(line, "^%s*```") or string.match(line, "^%s*~~~") then
				fenced = not fenced
			elseif not fenced then
				local rest = levelValue(line)
				if rest then
					local word = string.match(rest, "^([%w]+)") or ""
					if word ~= "easy" and RANK[word] == nil then
						return nil,
							`a review has the line "{trim(line)}": a Level line holds easy, normal or risky`
					end
					if word ~= "easy" and (best == nil or RANK[word] > RANK[best :: string]) then
						best = word
					end
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
