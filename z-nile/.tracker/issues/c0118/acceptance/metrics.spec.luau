--!strict
-- c0118 AC8 (design review 006 F3): metrics counts review rounds by the board's rule, `boardview.rounds`, not by a copy of
-- its patterns. c0116's metrics counts rounds in two functions of z-nile/engine/main.luau, `designRoundsIn(dir)` (a
-- folder's design rounds: the per-issue table, the per-raft roll-up, retired rafts) and `codeRounds(dir)` (a raft's
-- code rounds). Their outputs can't tell a copy from the shared rule (the patterns are the same), so this pins the
-- source, comments left out: each function's body calls `boardview.rounds`, and no string literal in it names review files
-- in any spelling (design review 007 F2). Other places in
-- main.luau that name review files for other purposes (z-raft's coherence review) are not metrics and are not read.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- The body of the function `name` declared in `text` (`local function <name>(` at any indent), up to the first line
-- that is that indent followed by `end`; nil when there is no such function.
local function body(text: string, name: string): string?
	local lines = string.split(text, "\n")
	for i, line in lines do
		local indent = string.match(line, `^(%s*)local function {name}%(`)
		if indent then
			local out = { line }
			for j = i + 1, #lines do
				table.insert(out, lines[j])
				if lines[j] == `{indent}end` then
					return table.concat(out, "\n")
				end
			end
			return nil
		end
	end
	return nil
end

-- `src` read as Luau, without its comments: the code with every comment removed (line `--` and long `--[[ ]]`,
-- `--[=[ ]=]`), and every string literal's contents (quoted '…', "…", `…` and long [[ ]] / [=[ ]=] brackets). Strings are
-- kept in the code too, so a call inside one still reads as text, never as a comment (design review 007 F2: a comment
-- naming `boardview.rounds(` must not count as the call, and a comment's `review` is not a pattern).
local function scan(src: string): (string, { string })
	local code: { string } = {}
	local strings: { string } = {}
	local i, n = 1, #src
	local function longClose(at: number): (number?, number?)
		local eq = string.match(src, "^%[(=*)%[", at)
		if not eq then
			return nil, nil
		end
		local close = "]" .. eq .. "]"
		local e = string.find(src, close, at + #eq + 2, true)
		return at + #eq + 2, e and (e + #close - 1) or n
	end
	while i <= n do
		local c = string.sub(src, i, i)
		if c == "-" and string.sub(src, i + 1, i + 1) == "-" then
			local first, last = longClose(i + 2)
			if first then
				i = (last :: number) + 1
			else
				local nl = string.find(src, "\n", i, true)
				i = nl or (n + 1)
			end
		elseif c == "[" and string.match(src, "^%[=*%[", i) then
			local first, last = longClose(i)
			local e = last :: number
			local closeLen = #(string.match(src, "^%[(=*)%[", i) :: string) + 2
			table.insert(strings, string.sub(src, first :: number, e - closeLen))
			table.insert(code, string.sub(src, i, e))
			i = e + 1
		elseif c == '"' or c == "'" or c == "`" then
			local j = i + 1
			while j <= n do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == c or (d == "\n" and c ~= "`") then
					break
				else
					j += 1
				end
			end
			table.insert(strings, string.sub(src, i + 1, j - 1))
			table.insert(code, string.sub(src, i, j))
			i = j + 1
		else
			table.insert(code, c)
			i += 1
		end
	end
	return table.concat(code), strings
end

-- what a counter's body does, read without comments: whether it calls `boardview.rounds(`, and the string literals
-- that name review files in any spelling (any literal containing `review`: `review%-%d`, `^design%-review%-(%d+)%.md$`,
-- a `string.format` template), which only a counter of its own needs
local function reads(b: string): (boolean, { string })
	local code, strings = scan(b)
	local own: { string } = {}
	for _, s in strings do
		if string.find(string.lower(s), "review", 1, true) then
			table.insert(own, s)
		end
	end
	return string.find(code, "boardview.rounds(", 1, true) ~= nil, own
end

return t.spec("c0118 metrics rounds", function(it)
	local text = fs.readFile(`{TOP}/z-nile/engine/main.luau`)

	it("the body finder reads a nested function to its own end", function()
		local sample =
			"local function a(x)\n\tlocal function codeRounds(dir)\n\t\tlocal _, c = boardview.rounds(paths)\n\tend\n\treturn 1\nend\n"
		local b = body(sample, "codeRounds")
		t.expect(b ~= nil).toBe(true)
		t.expect(string.find(b :: string, "return 1", 1, true)).toBe(nil)
		t.expect(body(sample, "missing")).toBe(nil)
	end)

	it(
		"the reading sees through comments and every spelling of a round-file pattern (design review 007 F2)",
		function()
			-- the intended counter: the call, no literal of its own (a "--note" string is not a comment)
			local calls, own = reads('local d = boardview.rounds(paths)\nlocal s = "--note review"')
			t.expect(calls).toBe(true)
			t.expect(#own).toBe(1) -- a literal naming review counts, even beside the call
			calls, own = reads("local d = boardview.rounds(paths)\nreturn d")
			t.expect(calls).toBe(true)
			t.expect(#own).toBe(0)
			-- evasion 1: a comment naming the call, with the counter's own pattern in the capture form
			calls, own = reads(
				'-- the same rule as boardview.rounds(paths)\nif string.match(n, "^design%-review%-(%d+)%.md$") then c += 1 end'
			)
			t.expect(calls).toBe(false)
			t.expect(#own).toBe(1)
			-- evasion 2: the call only inside a long comment; the short pattern spelling
			calls, own =
				reads('--[[ boardview.rounds(paths) ]]\nif string.find(n, "review%-%d") then c += 1 end')
			t.expect(calls).toBe(false)
			t.expect(#own).toBe(1)
			-- evasion 3: a long-bracket string and a format template
			calls, own =
				reads('local p = [[^review%-(%d+)%.md$]]\nlocal f = string.format("%s-review-%03d.md", k, i)')
			t.expect(#own).toBe(2)
			-- a comment that says "review" is no literal
			calls, own = reads("-- count the review rounds\nlocal d = boardview.rounds(paths)")
			t.expect(calls).toBe(true)
			t.expect(#own).toBe(0)
		end
	)

	for _, name in { "designRoundsIn", "codeRounds" } do
		it(`metrics' {name} counts through boardview.rounds and keeps no pattern of its own`, function()
			local b = body(text, name)
			if not b then
				error(`z-nile/engine/main.luau has no local function {name} (c0116's metrics counter)`)
			end
			local calls, own = reads(b :: string)
			t.expect(calls).toBe(true)
			if #own > 0 then
				error(`{name} names round files itself: {table.concat(own, ", ")}`)
			end
		end)
	end
end)
