--!strict
-- c0180: the engine records the command it is about to run in every directory ZN_SPEC_TRACE lists, as an empty file
-- named after the command; it refuses a bad entry or a failed write with exit 2 before doing anything, and changes
-- nothing else. Run on a trackerfix fixture under .cache/c0180-trace (the fixture's own copy of the engine).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local f = trackerfix.new("c0180-trace")
local traces = `{f.base}/traces`

local function freshDir(name: string): string
	local dir = `{traces}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	return dir
end

local function entries(dir: string): { string }
	local names = fs.readDir(dir)
	table.sort(names)
	return names
end

-- a spec that sets ZN_SPEC_TRACE appends what it inherited, so its own run still records the commands it ran
local inherited = process.env.ZN_SPEC_TRACE or ""
local function run(args: { string }, trace: string?): fixture.Result
	local value = trace or ""
	if value ~= "" and inherited ~= "" then
		value = `{value}:{inherited}`
	end
	return trackerfix.tr(f, f.main, args, { ZN_SPEC_TRACE = value })
end

local function refusedWith(r: fixture.Result, text: string)
	t.expect(r.code).toBe(2)
	t.expect((string.find(r.stderr, text, 1, true)) ~= nil).toBe(true)
end

local function clean()
	t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe("")
end

return t.spec("c0180 the engine traces the command it runs", function(it)
	it("an empty ZN_SPEC_TRACE records nothing anywhere", function()
		local dir = freshDir("empty")
		local r = run({ "list" }, "")
		t.expect(r.ok).toBe(true)
		t.expect(entries(dir)).toEqual({})
		t.expect(fs.isFile(`{f.main}/list`)).toBe(false)
		t.expect(fs.isFile(`{f.base}/list`)).toBe(false)
	end)

	it(
		"one directory gets exactly an empty file named after the command, and the output is unchanged",
		function()
			local plain = run({ "list" }, "")
			local dir = freshDir("one")
			local r = run({ "list" }, dir)
			t.expect(r.ok).toBe(true)
			t.expect(r.stdout).toBe(plain.stdout)
			t.expect(r.stderr).toBe(plain.stderr)
			t.expect(entries(dir)).toEqual({ "list" })
			t.expect(fs.readFile(`{dir}/list`)).toBe("")
		end
	)

	it("every listed directory gets the file, in a colon-separated list", function()
		local a, b = freshDir("a"), freshDir("b")
		t.expect(run({ "list" }, `{a}:{b}`).ok).toBe(true)
		t.expect(entries(a)).toEqual({ "list" })
		t.expect(entries(b)).toEqual({ "list" })
	end)

	it("two commands leave two files, and a command that fails is traced too", function()
		local dir = freshDir("two")
		t.expect(run({ "list" }, dir).ok).toBe(true)
		local missing = run({ "find", "c9999" }, dir)
		t.expect(missing.ok).toBe(false)
		t.expect(missing.code ~= 2).toBe(true)
		t.expect(entries(dir)).toEqual({ "find", "list" })
	end)

	it("an unknown command prints the usage as before and records nothing", function()
		local plain = run({ "nosuchcommand" }, "")
		local dir = freshDir("unknown")
		local r = run({ "nosuchcommand" }, dir)
		t.expect(r.code).toBe(plain.code)
		t.expect(r.stdout).toBe(plain.stdout)
		t.expect(entries(dir)).toEqual({})
	end)

	it("a relative entry refuses with exit 2 before the command does anything", function()
		local r = run({ "new", "issue", "c", "probe-relative", "--project", "z-nile" }, "rel/traces")
		refusedWith(r, "ZN_SPEC_TRACE entry rel/traces is not an absolute directory under a .cache folder")
		clean()
	end)

	it("an absolute entry outside every .cache folder refuses", function()
		-- the run's own temp folder: absolute, existing, and not under a .cache folder
		local tmp = (
			string.gsub(
				process.exec("pwd", { "-P" }, { cwd = process.env.TMPDIR or "/tmp" }).stdout,
				"%s+$",
				""
			)
		)
		t.expect((string.find(tmp, "/.cache/", 1, true))).toBe(nil)
		local r = run({ "new", "issue", "c", "probe-outside", "--project", "z-nile" }, tmp)
		refusedWith(r, `ZN_SPEC_TRACE entry {tmp} is not an absolute directory under a .cache folder`)
		clean()
	end)

	it("a missing directory refuses, even after a good entry", function()
		local good = freshDir("good")
		local missing = `{traces}/missing`
		local r = run({ "new", "issue", "c", "probe-missing", "--project", "z-nile" }, `{good}:{missing}`)
		refusedWith(r, `ZN_SPEC_TRACE entry {missing} is not an absolute directory under a .cache folder`)
		clean()
	end)

	it("a write that fails refuses with exit 2 and does nothing", function()
		local dir = freshDir("blocked")
		fs.writeDir(`{dir}/new`) -- a folder where the trace file goes: the rename over it fails
		local r = run({ "new", "issue", "c", "probe-blocked", "--project", "z-nile" }, dir)
		refusedWith(r, `cannot record the spec trace in {dir}`)
		clean()
	end)

	it("cleans up", function()
		fs.removeDir(f.base)
	end)
end)
