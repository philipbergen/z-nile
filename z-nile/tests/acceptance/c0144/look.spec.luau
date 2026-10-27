--!strict
-- c0144 AC2: how ./zn shows its output. Piped (a script, a spec, CI) every command prints plain text with no escape
-- sequence, the same with --color=never, --no-color or NO_COLOR; on a terminal (a pty from `script`) or with
-- --color=always it prints the rich look: aligned columns that fit the width, groups, colors, OSC 8 links to item
-- files, glyphs, and a summary line, keeping every fact of the plain text. NO_COLOR, --no-color and TERM=dumb keep the
-- layout and drop the color; a ./zn whose own stdout is a pipe stays plain inside a terminal run. ./zn check's lines
-- are colored by ac.sh on its own terminal. The usage text and zz-rules say so. Fixture under .cache/c0144-look.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ESC = "\27"
local OSC8 = "\27]8;;"
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local seed = require("./seed")
local LONG = seed.LONG

local f: trackerfix.Fixture

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function strip(text: string): string
	local s = string.gsub(text, "\27%]8;;[^\27]*\27\\", "")
	s = string.gsub(s, "\27%[[%d;]*m", "")
	return s
end

-- ./zn <args> in the fixture's main checkout, piped (as every spec runs it)
local function zn(args: { string }, env: { [string]: string }?): fixture.Result
	return trackerfix.tr(f, f.main, args, env)
end

local function quote(s: string): string
	return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- ./zn <args> on a pseudo-terminal (`script`), its output with the carriage returns and script's ^D removed
local function pty(args: { string }, env: { [string]: string }?, shell: string?): string
	local line = shell
		or (
			"bash scripts/tracker.sh "
			.. table.concat(
				(function()
					local q = {}
					for _, a in args do
						table.insert(q, quote(a))
					end
					return q
				end)(),
				" "
			)
		)
	local r = if process.os == "macos"
		then fixture.exec(f.main, "script", { "-q", "/dev/null", "bash", "-c", line }, { env = env })
		else fixture.exec(f.main, "script", { "-qec", line, "/dev/null" }, { env = env })
	local out = string.gsub(r.stdout .. r.stderr, "\r", "")
	out = string.gsub(out, "%^D\8\8", "")
	return out
end

-- the words of `text` (split on space, pipes and box lines), as a set
local function words(text: string): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for w in string.gmatch(strip(text), "[^%s|│─]+") do
		-- a word without the punctuation around it: "(both," and "both" are one word
		local bare = string.gsub(string.gsub(w, "^[%p]+", ""), "[%p]+$", "")
		if bare ~= "" then
			set[bare] = true
		end
	end
	return set
end

-- every word of the plain output is in the rich output: the look keeps every fact
local function keepsWords(plain: string, look: string): { string }
	local missing: { string } = {}
	local have = words(look)
	for w in pairs(words(plain)) do
		if not have[w] and not string.match(w, "^%-+$") then
			table.insert(missing, w)
		end
	end
	table.sort(missing)
	return missing
end

local WIDE = { COLUMNS = "200", LANG = "en_US.UTF-8" }
local NARROW = { COLUMNS = "60", LANG = "en_US.UTF-8" }

local COMMANDS = seed.COMMANDS

-- `extra` right after the command name, before its own arguments
local function before(args: { string }, extra: string): { string }
	local a = table.clone(args)
	table.insert(a, 2, extra)
	return a
end

local function with(args: { string }, extra: string): { string }
	local a = table.clone(args)
	table.insert(a, extra)
	return a
end

return t.spec("c0144 ./zn output in a terminal and in a pipe", function(it)
	it("sets up a fixture with items of every type and state in two projects", function()
		f = seed.build("c0144-look")
		local plain = zn({ "status" })
		t.expect({ ok = plain.ok, err = plain.stderr }).toEqual({ ok = true, err = "" })
		t.expect(has(plain.stdout, "f0001 new Speed boost escape")).toBe(true)
	end)

	it(
		"piped, no command prints an escape sequence, and --color=never, --no-color and NO_COLOR change nothing",
		function()
			for _, args in COMMANDS do
				local plain = zn(args)
				-- something was printed: "no escape" is not "no output"
				t.expect({ args = args, printed = plain.stdout ~= "" })
					.toEqual({ args = args, printed = true })
				t.expect({ args = args, esc = has(plain.stdout .. plain.stderr, ESC) })
					.toEqual({ args = args, esc = false })
				for _, other in
					{
						zn(with(args, "--color=never")),
						zn(with(args, "--no-color")),
						zn(before(args, "--no-color")), -- a switch: it takes no value, so the next word stays an argument
						zn(before(args, "--color=never")),
						zn(args, { NO_COLOR = "1" }),
						zn(args, WIDE),
					}
				do
					t.expect({ args = args, out = other.stdout, code = other.code }).toEqual({
						args = args,
						out = plain.stdout,
						code = plain.code,
					})
				end
			end
		end
	)

	it("--color=always prints the rich look, keeping every word of the plain text", function()
		for _, args in COMMANDS do
			local plain = zn(args)
			local rich = zn(with(args, "--color=always"), WIDE)
			t.expect({ args = args, esc = has(rich.stdout, ESC), code = rich.code }).toEqual({
				args = args,
				esc = true,
				code = plain.code,
			})
			local miss = keepsWords(plain.stdout, rich.stdout)
			if #miss > 0 then
				print("MISSING", table.concat(args, " "), table.concat(miss, " "))
			end
			t.expect({ args = args, missing = miss }).toEqual({
				args = args,
				missing = {},
			})
		end
	end)

	it("status groups by project then state, in aligned columns, with a summary of the counts", function()
		local out = strip(zn({ "status", "--color=always" }, WIDE).stdout)
		local pick = string.find(out, "pickman", 1, true) or 0
		local znile = string.find(out, "z-nile", 1, true) or 0
		t.expect(pick > 0 and znile > pick).toBe(true)
		local active = string.find(out, "ACTIVE (2)", 1, true) or 0
		local preparing = string.find(out, "PREPARING (1)", 1, true) or 0
		local new = string.find(out, "NEW (1)", 1, true) or 0
		t.expect(active > pick and preparing > active and new > preparing and znile > new).toBe(true)
		t.expect(has(out, "PREPARED (1)")).toBe(true)
		-- one column per field: the type, the state, the raft and the claim words
		t.expect(
			string.match(
				out,
				"c0004%s+chore%s+active%s+Frame roundtrip tolerance%s+R0003%s+jolly%-sunny%-copper"
			) ~= nil
		).toBe(true)
		t.expect(string.match(out, "\n([^\n]*items:[^\n]*)%s*$"))
			.toBe("5 items: 2 active · 1 preparing · 1 prepared · 1 new")
		-- the columns start at the same place in every row of a project
		local starts: { [number]: boolean } = {}
		for line in string.gmatch(out, "[^\n]+") do
			local s = string.find(line, "%s(Speed boost escape)")
				or string.find(line, "%s(Ghosts clip)")
				or string.find(line, "%s(Frame )")
			if s then
				starts[s] = true
			end
		end
		local n = 0
		for _ in starts do
			n += 1
		end
		t.expect(n).toBe(1)
	end)

	it(
		"at a narrow width only status and list cut words (titles, with an ellipsis); the rest wrap",
		function()
			for _, args in COMMANDS do
				if args[1] ~= "status" and args[1] ~= "list" then
					local plain = zn(args)
					local rich = zn(with(args, "--color=always"), NARROW)
					t.expect({ args = args, missing = keepsWords(plain.stdout, rich.stdout) }).toEqual({
						args = args,
						missing = {},
					})
				end
			end
		end
	)

	it("every line fits the width, and a long title ends in an ellipsis", function()
		for _, args in COMMANDS do
			local name = args[1]
			if name ~= "metrics" and name ~= "capture" then
				local out = strip(zn(with(args, "--color=always"), NARROW).stdout)
				for line in string.gmatch(out, "[^\n]+") do
					local w = utf8.len(line) or #line
					if w > 60 then
						print("WIDE", table.concat(args, " "), w, line)
					end
					t.expect({ args = args, line = line, fits = w <= 60 })
						.toEqual({ args = args, line = line, fits = true })
				end
			end
		end
		local status = strip(zn({ "status", "--color=always" }, NARROW).stdout)
		t.expect(has(status, LONG)).toBe(false)
		-- the claim words (not in the plain text) give way first, so the title keeps at least 24 columns
		t.expect(has(status, "jolly-sunny-copper")).toBe(false)
		local wide = strip(zn({ "status", "--color=always" }, WIDE).stdout)
		t.expect(has(wide, "jolly-sunny-copper")).toBe(true)
		t.expect(string.match(status, "A very long title[^\n]*…") ~= nil).toBe(true)
	end)

	it("links each item id to its document with OSC 8, unless ZN_HYPERLINKS=0", function()
		local out = zn({ "status", "--color=always" }, WIDE).stdout
		local url = `file://{f.main}/pickman/.tracker/issues/f0001/f0001.md`
		t.expect(has(out, OSC8 .. url .. "\27\\")).toBe(true)
		local members = zn({ "members", "R0003", "--color=always" }, WIDE).stdout
		t.expect(has(members, `{OSC8}file://{f.main}/pickman/.tracker/issues/active/c0004/c0004.md`))
			.toBe(true)
		local off = zn({ "status", "--color=always" }, { COLUMNS = "200", ZN_HYPERLINKS = "0" }).stdout
		t.expect(has(off, OSC8)).toBe(false)
		t.expect(has(off, ESC)).toBe(true)
	end)

	it(
		"links an active raft and its members' raft cell to its pull requests when origin is on GitHub",
		function()
			-- origin's configured URL looks like GitHub; git reaches the fixture's own origin through insteadOf
			local url = "https://github.com/acme/pickman.git"
			fixture.git(f.main, { "config", `url.{f.origin}.insteadOf`, url })
			fixture.git(f.main, { "remote", "set-url", "origin", url })
			local pr = OSC8 .. "https://github.com/acme/pickman/pulls?q=is%3Apr+head%3AR0003-s-r0003\27\\"
			for _, args in { { "status" }, { "list" } } do
				local out = zn(with(args, "--color=always"), WIDE).stdout
				local n, from = 0, 1
				while true do
					local at = string.find(out, pr, from, true)
					if not at then
						break
					end
					n += 1
					from = at + #pr
				end
				-- the raft's own row, and (status) its member's raft cell
				t.expect({ args = args, links = n >= (if args[1] == "status" then 2 else 1) }).toEqual({
					args = args,
					links = true,
				})
			end
			local plain = zn({ "status" }).stdout
			t.expect(has(plain, "github")).toBe(false)
			fixture.git(f.main, { "remote", "set-url", "origin", f.origin })
		end
	)

	it("uses ASCII glyphs and an ASCII ellipsis outside a UTF-8 locale", function()
		local out = zn({ "status", "--color=always" }, { COLUMNS = "60", LANG = "C", LC_ALL = "C" }).stdout
		t.expect((string.find(strip(out), "[\128-\255]"))).toBe(nil)
	end)

	it(
		"on a terminal it is rich and colored by itself; NO_COLOR, --no-color and TERM=dumb drop only the color",
		function()
			local auto = pty({ "status" }, { LANG = "en_US.UTF-8" })
			t.expect(has(auto, ESC)).toBe(true)
			t.expect(has(auto, "ACTIVE (2)")).toBe(true)
			-- script's terminal has no size (stty says 0 columns): the width falls back to 80
			for line in string.gmatch(strip(auto), "[^\n]+") do
				t.expect({ line = line, fits = (utf8.len(line) or #line) <= 80 })
					.toEqual({ line = line, fits = true })
			end
			for _, run in
				{
					pty({ "status" }, { NO_COLOR = "1" }),
					pty({ "status", "--no-color" }, {}),
					pty({ "status", "--color=never" }, {}),
					pty({ "status" }, { TERM = "dumb" }),
				}
			do
				t.expect({ esc = has(run, ESC), layout = has(run, "ACTIVE (2)") })
					.toEqual({ esc = false, layout = true })
			end
		end
	)

	it("a ./zn whose stdout is a pipe stays plain inside a terminal run, as in $(...) and | cat", function()
		local piped = pty({}, {}, "bash scripts/tracker.sh status | cat")
		t.expect(has(piped, ESC)).toBe(false)
		t.expect(has(piped, "f0001 new Speed boost escape")).toBe(true)
		local captured = pty({}, {}, 'echo "[$(bash scripts/tracker.sh members R0003)]"')
		t.expect(has(captured, "[pickman/.tracker/issues/active/c0004]")).toBe(true)
	end)

	it(
		"./zn check colors PASS on a terminal, is plain piped, and --no-color keeps its lines plain",
		function()
			local piped = zn({ "check", "c0004" })
			t.expect(piped.ok).toBe(true)
			t.expect(has(piped.stdout, "\nPASS  AC1: it holds\n")).toBe(true)
			t.expect(has(piped.stdout, ESC)).toBe(false)
			local tty = pty({ "check", "c0004" }, {})
			t.expect(has(tty, "\27[32;1mPASS\27[0m  AC1: it holds")).toBe(true)
			local no = pty({ "check", "c0004", "--no-color" }, {})
			t.expect(has(no, ESC)).toBe(false)
			t.expect(has(no, "PASS  AC1: it holds")).toBe(true)
			-- ac.sh's own rule (it decides for its own stdout) honours TERM=dumb and NO_COLOR as the engine's does
			local envs: { { [string]: string } } = { { TERM = "dumb" }, { NO_COLOR = "1" } }
			for _, env in envs do
				local run = pty({ "check", "c0004" }, env)
				t.expect({ env = env, esc = has(run, ESC), pass = has(run, "PASS  AC1: it holds") })
					.toEqual({ env = env, esc = false, pass = true })
			end
			-- ac.sh decides for its own stdout: a check.sh run directly on a terminal is colored, and plain with TERM=dumb or
			-- NO_COLOR (here no ./zn stands between, to pass NO_COLOR on)
			local direct = pty({}, {}, "bash pickman/.tracker/issues/active/c0004/check.sh")
			t.expect(has(direct, "\27[32;1mPASS\27[0m  AC1: it holds")).toBe(true)
			for _, env in envs do
				local run = pty({}, env, "bash pickman/.tracker/issues/active/c0004/check.sh")
				t.expect({
					direct = true,
					env = env,
					esc = has(run, ESC),
					pass = has(run, "PASS  AC1: it holds"),
				}).toEqual({
					direct = true,
					env = env,
					esc = false,
					pass = true,
				})
			end
		end
	)

	it(
		"a refusal is colored on a terminal's stderr and today's text when piped; a bad --color is refused",
		function()
			local piped = zn({ "members" })
			t.expect({ ok = piped.ok, err = piped.stderr })
				.toEqual({ ok = false, err = "usage: members <R-id>\n" })
			local tty = pty({ "members" }, { LANG = "en_US.UTF-8" })
			t.expect(has(tty, "\27[31;1m✖ usage: members <R-id>\27[0m")).toBe(true)
			local bad = zn({ "status", "--color=sometimes" })
			t.expect({ ok = bad.ok, err = bad.stderr }).toEqual({
				ok = false,
				err = '--color takes auto, always or never (got "sometimes")\n',
			})
		end
	)

	it("the usage text and zz-rules say how output is shown", function()
		local usage = zn({}).stdout
		t.expect(has(usage, "--color=auto|always|never")).toBe(true)
		t.expect(has(usage, "--no-color")).toBe(true)
		local rules = fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
		t.expect(has(rules, "NO_COLOR")).toBe(true)
		t.expect(has(rules, "--color=always")).toBe(true)
		t.expect(has(rules, "plain text when piped")).toBe(true)
	end)

	it("cleans up", function()
		local base = `{fixture.physical(".")}/.cache/c0144-look`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
