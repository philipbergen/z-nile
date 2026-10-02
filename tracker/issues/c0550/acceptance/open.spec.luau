--!strict
-- c0550: `tracker.sh board` opens the written page in the default browser unless `-O` is given.
-- Every case puts stub openers (`open`, `xdg-open`) first on PATH, so no browser ever starts; a stub
-- appends its arguments to a log, one line per call, and exits with the code the case chose.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local DIR = ".cache/c0550-open"
local OUT = `{DIR}/page.html`
local ABS = `{process.cwd}{OUT}`
local LOG = `{process.cwd}{DIR}/opened.log`

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- a clean fixture directory with stub openers that exit with `code`
local function fresh(code: number)
	if fs.isDir(DIR) then
		fs.removeDir(DIR)
	end
	fs.writeDir(`{DIR}/bin`)
	for _, name in { "open", "xdg-open" } do
		fs.writeFile(`{DIR}/bin/{name}`, `#!/bin/sh\necho "$@" >> "{LOG}"\nexit {code}\n`)
		process.exec("chmod", { "+x", `{DIR}/bin/{name}` })
	end
end

local function board(args: { string }): Result
	local full = { "board" }
	for _, a in args do
		table.insert(full, a)
	end
	return process.exec("scripts/tracker.sh", full, {
		env = { PATH = `{process.cwd}{DIR}/bin:{process.env.PATH or ""}` },
	})
end

-- one entry per opener call: the arguments it got
local function calls(): { string }
	local out = {}
	if fs.isFile(LOG) then
		for line in string.gmatch(fs.readFile(LOG), "[^\n]+") do
			table.insert(out, line)
		end
	end
	return out
end

return t.spec("c0550 board opens by default", function(it)
	it("with no flag, writes the page and opens it once, by the absolute path it prints", function()
		fresh(0)
		local r = board({ "--out", OUT })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(OUT)).toBe(true)
		t.expect(trim(r.stdout)).toBe(ABS)
		t.expect(calls()).toEqual({ ABS })
		fs.removeDir(DIR)
	end)

	it("-O writes the page and prints its path, but runs no opener", function()
		fresh(0)
		local r = board({ "-O", "--out", OUT })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(OUT)).toBe(true)
		t.expect(trim(r.stdout)).toBe(ABS)
		t.expect(calls()).toEqual({})
		fs.removeDir(DIR)
	end)

	it("-O after --out works too, and takes no value of its own", function()
		fresh(0)
		local r = board({ "--out", OUT, "-O" })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(OUT)).toBe(true)
		t.expect(calls()).toEqual({})
		-- with a stray word after -O, the word is a positional argument and the command is refused
		local stray = board({ "-O", "x", "--out", OUT .. ".2" })
		t.expect(stray.ok).toBe(false)
		t.expect(fs.isFile(OUT .. ".2")).toBe(false)
		t.expect(calls()).toEqual({})
		fs.removeDir(DIR)
	end)

	it("--open is still accepted and opens, as the default does", function()
		fresh(0)
		local r = board({ "--open", "--out", OUT })
		t.expect(r.ok).toBe(true)
		t.expect(calls()).toEqual({ ABS })
		fs.removeDir(DIR)
	end)

	it("--open with -O is refused: nothing is written and nothing is opened", function()
		fresh(0)
		for _, args in { { "--open", "-O", "--out", OUT }, { "-O", "--out", OUT, "--open" } } do
			local r = board(args)
			t.expect(r.ok).toBe(false)
			t.expect(string.find(r.stderr, "-O", 1, true) ~= nil).toBe(true)
			t.expect(fs.isFile(OUT)).toBe(false)
		end
		t.expect(calls()).toEqual({})
		fs.removeDir(DIR)
	end)

	it("an opener that fails warns on stderr; the page is still written and the exit code is 0", function()
		fresh(3)
		local r = board({ "--out", OUT })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(OUT)).toBe(true)
		t.expect(#calls()).toBe(1)
		t.expect(string.find(r.stderr, "warning:", 1, true) ~= nil).toBe(true)
		t.expect(trim(r.stdout)).toBe(ABS)
		fs.removeDir(DIR)
	end)

	it("the usage line and the tracker skill's board row document -O", function()
		local usage = process.exec("scripts/tracker.sh", {})
		t.expect(string.find(usage.stdout, "board [--out PATH] [-O]", 1, true) ~= nil).toBe(true)
		local row = ""
		for line in string.gmatch(fs.readFile(".claude/skills/tracker/SKILL.md"), "[^\n]+") do
			if string.sub(line, 1, 10) == "| board | " then
				row = line
			end
		end
		t.expect(string.find(row, "`tracker.sh board [--out PATH] [-O]`", 1, true) ~= nil).toBe(true)
		t.expect(string.find(row, "unless `-O`", 1, true) ~= nil).toBe(true)
	end)

	it("the board workflow builds with -O, so CI never tries to start a browser", function()
		local text = fs.readFile(".github/workflows/board.yml")
		t.expect(
			string.find(text, "run: scripts/tracker.sh board --out dist/board.html -O\n", 1, true) ~= nil
		)
			.toBe(true)
	end)
end)
