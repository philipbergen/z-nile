--!strict
-- An issue's guesses.md (f0399): every choice a worker made that the approved contract did not make.
-- Pure: texts in, texts out. `./zn guess` writes the file, the approval contract hashes it.
--   # guesses
--   - G1 (design, 2026-11-16): <what was open>. Chose: <the choice>. Why: <the evidence>.
-- Oldest first, numbered from G1 with no gap. A field holds no line break and neither mark.

local guesses = {}

export type Guess = { id: string, step: string, when: string, open: string, chose: string, why: string }

guesses.FILE = "guesses.md"
guesses.STEPS = { "design", "raft", "build" }

local HEADER = "# guesses"
local CHOSE = " Chose: "
local WHY = " Why: "
local DAY = "^%d%d%d%d%-%d%d%-%d%d$"

local function isStep(step: string): boolean
	return table.find(guesses.STEPS, step) ~= nil
end

local function fieldProblem(name: string, value: string): string?
	if string.match(value, "^%s*$") then
		return `{name} is empty`
	end
	if string.find(value, "[\r\n]") then
		return `{name} has a line break`
	end
	if string.find(value, CHOSE, 1, true) or string.find(value, WHY, 1, true) then
		return `{name} holds a mark ("{CHOSE}" or "{WHY}")`
	end
	return nil
end

function guesses.parse(text: string): ({ Guess }?, string?)
	local norm = (string.gsub(text, "\r\n", "\n"))
	local lines: { string } = {}
	for line in string.gmatch(norm .. "\n", "(.-)\n") do
		table.insert(lines, line)
	end
	while #lines > 0 and lines[#lines] == "" do
		table.remove(lines)
	end
	if lines[1] ~= HEADER then
		return nil, `the first line must be "{HEADER}"`
	end
	local out: { Guess } = {}
	for i = 2, #lines do
		local line = lines[i]
		local n, step, when, rest = string.match(line, "^%- G(%d+) %((%a+), ([%d%-]+)%): (.*)$")
		if not n then
			return nil, `line {i} is not a guess: "{line}"`
		end
		if tonumber(n) ~= #out + 1 or n ~= tostring(#out + 1) then
			return nil, `line {i} is G{n}, expected G{#out + 1}`
		end
		if not isStep(step :: string) then
			return nil, `G{n} has an unknown step "{step}"`
		end
		if not string.match(when :: string, DAY) then
			return nil, `G{n}'s date is not YYYY-MM-DD`
		end
		local body = rest :: string
		local c = string.find(body, CHOSE, 1, true)
		local w = c and string.find(body, WHY, c + #CHOSE, true)
		if not c or not w then
			return nil, `G{n} needs "{CHOSE}" and then "{WHY}"`
		end
		local open = string.sub(body, 1, c - 1)
		local chose = string.sub(body, c + #CHOSE, w - 1)
		local why = string.sub(body, w + #WHY)
		for name, value in { open = open, chose = chose, why = why } :: { [string]: string } do
			local problem = fieldProblem(name, value)
			if problem then
				return nil, `G{n}: {problem}`
			end
		end
		table.insert(out, {
			id = `G{n}`,
			step = step :: string,
			when = when :: string,
			open = open,
			chose = chose,
			why = why,
		})
	end
	return out, nil
end

function guesses.render(list: { Guess }): string
	local lines = { HEADER }
	for _, g in list do
		table.insert(lines, `- {g.id} ({g.step}, {g.when}): {g.open}{CHOSE}{g.chose}{WHY}{g.why}`)
	end
	return table.concat(lines, "\n") .. "\n"
end

function guesses.append(
	text: string?,
	step: string,
	when: string,
	open: string,
	chose: string,
	why: string
): (string?, string?)
	local list: { Guess } = {}
	if text and text ~= "" then
		local parsed, err = guesses.parse(text)
		if not parsed then
			return nil, `{guesses.FILE} does not parse: {err}`
		end
		list = parsed
	end
	if not isStep(step) then
		return nil, `unknown step "{step}" ({table.concat(guesses.STEPS, ", ")})`
	end
	if not string.match(when, DAY) then
		return nil, "the date is not YYYY-MM-DD"
	end
	for _, pair in { { "--open", open }, { "--chose", chose }, { "--why", why } } do
		local problem = fieldProblem(pair[1], pair[2])
		if problem then
			return nil, problem
		end
	end
	table.insert(
		list,
		{ id = `G{#list + 1}`, step = step, when = when, open = open, chose = chose, why = why }
	)
	return guesses.render(list), nil
end

-- Is `new` the guesses of `old` with nothing removed or changed, and any number added? A text that does not
-- parse extends nothing. A missing `old` is extended by anything that parses, and by nothing at all.
function guesses.extends(old: string?, new: string?): boolean
	local was: { Guess } = {}
	if old and old ~= "" then
		local parsed = guesses.parse(old)
		if not parsed then
			return false
		end
		was = parsed
	end
	if not new or new == "" then
		return #was == 0
	end
	local now = guesses.parse(new)
	if not now or #now < #was then
		return false
	end
	for i, g in was do
		local n = now[i]
		if
			n.step ~= g.step
			or n.when ~= g.when
			or n.open ~= g.open
			or n.chose ~= g.chose
			or n.why ~= g.why
		then
			return false
		end
	end
	return true
end

function guesses.has(text: string?, id: string): boolean
	if not text or text == "" then
		return false
	end
	local list = guesses.parse(text)
	if not list then
		return false
	end
	for _, g in list do
		if g.id == id then
			return true
		end
	end
	return false
end

return guesses
