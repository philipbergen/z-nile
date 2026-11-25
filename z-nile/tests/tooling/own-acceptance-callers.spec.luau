--!strict
-- d0297: no gate, hook or forwarder passes `--own-acceptance` (the flag that lets the selector print a layer's own
-- sequestered acceptance specs; only `./zn finish` passes it). Its watch file names the files that run the selector,
-- so a change to one of them reruns this scan; the scan itself reads every file a gate or hook runs from.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- The code part of one line: the line up to its comment. A comment starts at the marker (`--` in a .luau file, `#` in
-- any other) when only whitespace comes before it on the line, or when whitespace comes on both sides of it, and in
-- either case only outside a string literal (`"`, `'` or a backtick; a backslash escapes in Luau and inside a shell's
-- double quotes), so `"lune run z-nile/affected -- --own-acceptance"` stays code (review 001 F1). A Luau long string
-- (`[[...]]`) is not tracked: this is a guard over one line at a time.
local function codeOf(line: string, luau: boolean): string
	local marker = if luau then "--" else "#"
	local quote: string? = nil
	local escaped = false
	local leading = true
	for i = 1, #line do
		local c = string.sub(line, i, i)
		if quote then
			if escaped then
				escaped = false
			elseif c == "\\" and (luau or quote == '"') then
				escaped = true
			elseif c == quote then
				quote = nil
			end
		else
			if string.sub(line, i, i + #marker - 1) == marker then
				if leading then
					return ""
				end
				local before = string.sub(line, i - 1, i - 1)
				local after = string.sub(line, i + #marker, i + #marker)
				if string.match(before, "^%s$") and string.match(after, "^%s$") then
					return string.sub(line, 1, i - 1)
				end
			end
			if c == '"' or c == "'" or c == "`" then
				quote = c
			end
			if not string.match(c, "^%s$") then
				leading = false
			end
		end
	end
	return line
end

-- uses of the flag in code: a comment that names it is not a use
local function uses(text: string, luau: boolean): number
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		for _ in string.gmatch(codeOf(line, luau), "%-%-own%-acceptance") do
			n += 1
		end
	end
	return n
end

return t.spec("d0297 no gate, hook or forwarder passes --own-acceptance", function(it)
	it("the files a gate, hook or forwarder runs from never use the flag", function()
		local listed = process.exec("git", {
			"ls-files",
			"--",
			"zn",
			"scripts",
			":(glob)z-nile/*.sh",
			":(glob)z-nile/*.luau",
			"z-nile/bin",
			"z-nile/shim",
			"z-nile/lib",
			"z-nile/scripts",
			".claude",
			":(exclude,glob)**/.tracker/**",
		}, { cwd = TOP })
		t.expect(listed.ok).toBe(true)
		local seen = 0
		local holders: { string } = {}
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			-- the selector defines the flag; it is the one file allowed to name it in code
			if path ~= "z-nile/affected.luau" and fs.isFile(`{TOP}/{path}`) then
				seen += 1
				if uses(fs.readFile(`{TOP}/{path}`), string.sub(path, -5) == ".luau") > 0 then
					table.insert(holders, path)
				end
			end
		end
		t.expect(seen > 0).toBe(true)
		t.expect(holders).toEqual({})
		t.expect(fs.isFile(`{TOP}/z-nile/check.sh`)).toBe(true)
	end)

	it("the scan counts the flag in code and in strings, and not in comments", function()
		local FLAG = "--own" .. "-acceptance"
		-- Luau: an argv, a shell string holding ` -- ` before the flag, an escaped quote; comments are not uses
		t.expect(uses(`local argv = \{ "run", "z-nile/affected", "--", "{FLAG}" }`, true)).toBe(1)
		t.expect(
			uses(`sh.run("bash", \{ "-c", "lune run z-nile/affected -- --project z-nile {FLAG}" })`, true)
		)
			.toBe(1)
		t.expect(uses(`local s = 'lune run z-nile/affected -- {FLAG}' -- the shell form`, true)).toBe(1)
		t.expect(uses(`local s = "a \\" -- {FLAG}"`, true)).toBe(1)
		t.expect(uses(`x() -- names {FLAG}`, true)).toBe(0)
		t.expect(uses(`  -- {FLAG}`, true)).toBe(0)
		t.expect(uses(`--{FLAG}`, true)).toBe(0)
		-- shell: a command, a quoted `#`; comments are not uses
		t.expect(uses(`lune run z-nile/affected -- {FLAG}`, false)).toBe(1)
		t.expect(uses(`echo "a # {FLAG}"`, false)).toBe(1)
		t.expect(uses(`# {FLAG}`, false)).toBe(0)
		t.expect(uses(`echo hi # {FLAG}`, false)).toBe(0)
		-- every line counts
		t.expect(uses(`a {FLAG}\nb {FLAG}\n# {FLAG}`, false)).toBe(2)
	end)
end)
