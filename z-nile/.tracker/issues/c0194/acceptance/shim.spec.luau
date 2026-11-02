--!strict
-- c0194: macOS mktemp ignores TMPDIR, so z-nile/bin/mktemp puts a template-less tree in TMPDIR. The runner embeds the
-- same text (fence.MKTEMP_SHIM); an agent session gets the file itself first on PATH (hook.spec).
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local here = trim(process.exec("pwd", { "-P" }).stdout)
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local SHIM = `{root}/z-nile/bin/mktemp`
local base = `{here}/.cache/c0194-shim`
local tmpdir = `{base}/checkout/.cache/.tmp`

local function run(
	args: { string },
	env: { [string]: string }
): { ok: boolean, code: number, stdout: string, stderr: string }
	env.PATH = process.env.PATH or ""
	return process.exec("sh", { SHIM, table.unpack(args) }, { env = env })
end

local function inside(path: string, dir: string): boolean
	return string.sub(path, 1, #dir + 1) == dir .. "/"
end

return t.spec("c0194 the mktemp that honours TMPDIR", function(it)
	local function fresh()
		process.exec("rm", { "-rf", base })
		fs.writeDir(tmpdir)
	end

	it("the runner embeds the file's exact text and the file is executable", function()
		t.expect(fence.MKTEMP_SHIM).toBe(fs.readFile(SHIM))
		t.expect(process.exec("test", { "-x", SHIM }).ok).toBe(true)
	end)

	it("no template, -d, -t and -d with a prefix land in TMPDIR", function()
		fresh()
		local f = trim(run({}, { TMPDIR = tmpdir }).stdout)
		t.expect(inside(f, tmpdir) and fs.isFile(f)).toBe(true)
		local d = trim(run({ "-d" }, { TMPDIR = tmpdir }).stdout)
		t.expect(inside(d, tmpdir) and fs.isDir(d)).toBe(true)
		local named = trim(run({ "-t", "foo" }, { TMPDIR = tmpdir .. "/" }).stdout)
		t.expect(inside(named, tmpdir) and string.find(named, "/foo.", 1, true) ~= nil).toBe(true)
		local cluster = run({ "-dt", "baz" }, { TMPDIR = tmpdir })
		t.expect(inside(trim(cluster.stdout), tmpdir) and fs.isDir(trim(cluster.stdout))).toBe(true)
		t.expect(string.find(cluster.stdout, "/baz.", 1, true) ~= nil).toBe(true)
		local both = run({ "-d", "-t", "bar" }, { TMPDIR = tmpdir })
		t.expect(inside(trim(both.stdout), tmpdir) and fs.isDir(trim(both.stdout))).toBe(true)
	end)

	it("a template or -p names its own place and is passed through", function()
		fresh()
		local elsewhere = `{base}/elsewhere`
		fs.writeDir(elsewhere)
		local viaTemplate = trim(run({ "-d", `{elsewhere}/x.XXXXXX` }, { TMPDIR = tmpdir }).stdout)
		t.expect(inside(viaTemplate, elsewhere)).toBe(true)
		local viaP = trim(run({ "-d", "-p", elsewhere }, { TMPDIR = tmpdir }).stdout)
		t.expect(inside(viaP, elsewhere)).toBe(true)
		t.expect(#fs.readDir(tmpdir)).toBe(0)
	end)

	it(
		"a TMPDIR outside .cache/.tmp is used, with a warning; an unset or missing one falls back with a warning",
		function()
			fresh()
			local plain = `{base}/plain`
			fs.writeDir(plain)
			local r = run({ "-d" }, { TMPDIR = plain })
			t.expect(inside(trim(r.stdout), plain)).toBe(true)
			-- (a checkout that itself lies under a .cache/.tmp, such as a jailed clone, has no folder outside one to warn about)
			if string.find(here, "/.cache/.tmp/", 1, true) == nil then
				t.expect(string.find(r.stderr, "not under a .cache/.tmp folder", 1, true) ~= nil).toBe(true)
			end
			local quiet = run({ "-d" }, { TMPDIR = tmpdir })
			t.expect(quiet.stderr).toBe("")
			-- the system temp folder (which the jail closes, so only the warning is asserted)
			local r2 = run({ "-d" }, { TMPDIR = `{base}/missing` })
			t.expect(string.find(r2.stderr, "unset or not a folder", 1, true) ~= nil).toBe(true)
		end
	)
end)
