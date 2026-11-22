--!strict
-- f0427 AC3 (step 2, cache hardening): the cache zn runs from is verified on every run and is the user's own.
-- One sentence of AC3 per group of cases, each tampering with the REAL cache of a real build (the extracted Lune and
-- engine) in a fixture under .cache, then running the built zn and asserting the designed outcome:
--   1. "A changed byte in the extracted lune is detected and re-extracted before exec": a flipped byte, a truncated lune, a
--      deleted lune and a decoy lune (a script that would leave a marker if run) are each replaced by the embedded Lune
--      before anything runs; the marker never appears; the replaced folder is kept aside, not deleted.
--   2. The same for the engine files (changed byte, truncated, deleted, a file planted), and a good cache is left alone.
--   3. "The cache folders have mode 0700": created fresh under umask 0, parents and every folder 0700, no file readable
--      or writable by group or others.
--   4. "A symlink in the cache path is refused": the cache folder, the extracted folder, bin, the Lune and an engine file,
--      each swapped for a link; a hard link to the Lune; each refused with a message naming the path, nothing run.
--   5. A folder or runtime file writable by group or others is refused naming it; one only readable is not.
--   6. "A relative XDG_CACHE_HOME is ignored": nothing is made beside the working folder; an absolute one the user owns
--      is used; an absolute one that is not the user's (/usr) is ignored.
--   7. HOME unset with no ZN_CACHE is a message naming HOME.
-- NOT checked here, and checked in go/internal/payload/cache_test.go and go/cmd/zn/main_test.go instead:
--   - a cache folder or runtime file OWNED BY ANOTHER USER is refused (needs root to create here; the Go tests swap the
--     owner lookup), and XDG_CACHE_HOME owned by another user is ignored (here only /usr stands in for it);
--   - an exec that fails on a noexec mount names the folder and ZN_CACHE (needs a mount; the Go test fakes the failure).
-- Every zn runs with a fixture HOME, an absolute throwaway ZN_CACHE under .cache and the runner's guard stubs first on PATH.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local zn = require("./lib/zn")

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function sha(bytes: string): string
	return serde.hash("sha256", bytes)
end

local function sh(script: string): process.SpawnResult
	return process.exec("sh", { "-c", script })
end

-- Every regular file under dir (relative path -> sha256 of its bytes).
local function snapshot(dir: string, rel: string?, out: { [string]: string }?): { [string]: string }
	local files: { [string]: string } = out or {}
	local prefix = rel or ""
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			snapshot(path, `{prefix}{name}/`, files)
		else
			files[`{prefix}{name}`] = sha(fs.readFile(path))
		end
	end
	return files
end

local function flip(bytes: string, at: number): string
	local b = string.byte(bytes, at)
	return string.sub(bytes, 1, at - 1) .. string.char(bit32.bxor(b, 1)) .. string.sub(bytes, at + 1)
end

local function same(a: { [string]: string }, b: { [string]: string }): boolean
	for k, v in a do
		if b[k] ~= v then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function stales(zndir: string): { string }
	local out = {}
	for _, name in fs.readDir(zndir) do
		if string.sub(name, 1, 7) == ".stale-" then
			table.insert(out, `{zndir}/{name}`)
		end
	end
	return out
end

local built: zn.Built? = nil

local function bin(): string
	if built == nil then
		zn.needGo()
		local b = zn.build("cache", zn.hostLuneArgs())
		if not b.ok then
			error(`the build failed ({b.code}): {b.stderr}`, 2)
		end
		built = b
	end
	return (built :: zn.Built).bin
end

type Ctx = {
	bin: string,
	tracker: string,
	cache: string, -- the ZN_CACHE of this case
	zndir: string, -- <cache>/zn
	dir: string, -- <cache>/zn/<id>
	lune: string,
	good: { [string]: string }, -- every extracted file's digest, taken right after the first run
	run: (args: { string }, extra: { [string]: string }?) -> any,
}

-- A fresh tracker and a fresh cache, extracted by one cold run that must work.
local function setup(label: string): Ctx
	local b = bin()
	local tracker = zn.tracker(`f0427-cache/{label}/tracker`)
	local cache = zn.fresh(`f0427-cache/{label}/cache`)
	local first = zn.run(b, tracker, cache, { "list" })
	t.expect(first.code).toBe(0)
	t.expect(has(first.stdout, "f0001")).toBe(true)
	local v = zn.run(b, tracker, cache, { "version" })
	local id = string.match(v.stdout, "payload (%x+)")
	t.expect(id ~= nil).toBe(true)
	local dir = `{cache}/zn/{id}`
	t.expect(fs.isDir(dir)).toBe(true)
	local ctx: Ctx = {
		bin = b,
		tracker = tracker,
		cache = cache,
		zndir = `{cache}/zn`,
		dir = dir,
		lune = `{dir}/bin/lune`,
		good = snapshot(dir),
		run = function(args, extra)
			return zn.run(b, tracker, cache, args, extra)
		end,
	}
	t.expect(ctx.good["bin/lune"] ~= nil and ctx.good["z-nile/engine/main.luau"] ~= nil).toBe(true)
	return ctx
end

-- A decoy that would leave a marker if anything ran it.
local function decoyScript(marker: string): string
	return `#!/bin/sh\ntouch "{marker}"\nexit 97\n`
end

-- Runs `list` and asserts the run worked, the folder is the embedded payload again, and the marker never appeared.
local function expectRepaired(c: Ctx, marker: string?)
	local r = c.run({ "list" })
	t.expect(r.code).toBe(0)
	t.expect(has(r.stdout, "f0001")).toBe(true)
	if marker then
		t.expect(fs.isFile(marker)).toBe(false) -- the tampered runtime was never executed
	end
	t.expect(same(snapshot(c.dir), c.good)).toBe(true) -- every file is back, byte for byte, and nothing else is there
end

-- Runs `list` and asserts the refusal: exit 1, the message names `path`, nothing was started or written.
local function expectRefused(
	c: Ctx,
	path: string,
	word: string,
	marker: string?,
	extra: { [string]: string }?
)
	local r = c.run({ "list" }, extra)
	t.expect(r.code).toBe(1)
	t.expect(has(r.stderr, path)).toBe(true)
	t.expect(has(r.stderr, word)).toBe(true)
	t.expect(has(r.stdout, "f0001")).toBe(false)
	if marker then
		t.expect(fs.isFile(marker)).toBe(false)
	end
end

return t.spec("f0427 AC3 the cache is verified each run, private, and refuses links", function(it)
	it(
		"a changed byte in the extracted lune is replaced before anything runs (and the old folder is kept)",
		function()
			local c = setup("lune-flip")
			local original = fs.readFile(c.lune)
			fs.writeFile(c.lune, flip(original, #original - 5)) -- same size, one bit
			t.expect(sha(fs.readFile(c.lune)) == c.good["bin/lune"]).toBe(false)
			expectRepaired(c)
			-- the folder that failed the comparison may be in use by another zn: kept aside, never deleted
			local kept = stales(c.zndir)
			t.expect(#kept).toBe(1)
			t.expect(fs.readFile(`{kept[1]}/bin/lune`) == flip(original, #original - 5)).toBe(true)
			-- and the repaired folder verifies, so the next run neither moves it nor writes: still one stale folder
			t.expect(c.run({ "list" }).code).toBe(0)
			t.expect(#stales(c.zndir)).toBe(1)
		end
	)

	it("a decoy lune is never executed: it is replaced by the embedded one first", function()
		local c = setup("lune-decoy")
		local marker = `{c.cache}/decoy-ran`
		fs.writeFile(c.lune, decoyScript(marker))
		process.exec("chmod", { "700", c.lune })
		expectRepaired(c, marker)
		-- a decoy of the very same size as the Lune, so a size comparison alone cannot tell it
		local size = #fs.readFile(c.lune)
		local head = decoyScript(marker)
		fs.writeFile(c.lune, head .. string.rep("#", size - #head))
		process.exec("chmod", { "700", c.lune })
		t.expect(#fs.readFile(c.lune)).toBe(size)
		expectRepaired(c, marker)
	end)

	it("a truncated or a deleted lune is put back", function()
		local c = setup("lune-gone")
		process.exec("truncate", { "-s", "100", c.lune })
		expectRepaired(c)
		fs.removeFile(c.lune)
		expectRepaired(c)
	end)

	it("a changed, truncated, deleted or planted engine file is put back", function()
		local c = setup("engine")
		local main = `{c.dir}/z-nile/engine/main.luau`
		local text = fs.readFile(main)
		fs.writeFile(main, flip(text, 3)) -- same size, one bit
		expectRepaired(c)
		fs.writeFile(main, string.sub(text, 1, 10)) -- truncated
		expectRepaired(c)
		fs.removeFile(main) -- deleted
		expectRepaired(c)
		fs.writeFile(`{c.dir}/z-nile/engine/planted.luau`, 'print("planted")\n') -- a file the payload does not carry
		expectRepaired(c)
		t.expect(fs.isFile(`{c.dir}/z-nile/engine/planted.luau`)).toBe(false)
		fs.removeFile(`{c.dir}/.ok`) -- the marker alone is not what is trusted: a deleted one is put back too
		expectRepaired(c)
		-- the folders the payload carries, removed whole
		fs.removeDir(`{c.dir}/z-nile/lib`)
		expectRepaired(c)
		-- the replaced folders were all kept aside, each with what was wrong in it
		t.expect(#stales(c.zndir) >= 5).toBe(true)
	end)

	it("a good cache is left alone: no run re-extracts or moves it aside", function()
		local c = setup("untouched")
		local before = fs.metadata(c.lune).modifiedAt
		for _ = 1, 3 do
			local r = c.run({ "list" })
			t.expect(r.code).toBe(0)
		end
		local b = c.run({ "board", "-O" }) -- -O: the board is not opened
		t.expect(b.code).toBe(0)
		t.expect(zn.opened()).toBe("")
		t.expect(#stales(c.zndir)).toBe(0)
		local after = fs.metadata(c.lune).modifiedAt
		t.expect(before ~= nil and after ~= nil and before.unixTimestampMillis == after.unixTimestampMillis)
			.toBe(true)
		t.expect(same(snapshot(c.dir), c.good)).toBe(true)
	end)

	it("every folder is created 0700 and no file is open to group or others, whatever the umask", function()
		local b = bin()
		local tracker = zn.tracker("f0427-cache/mode/tracker")
		local top = zn.fresh("f0427-cache/mode/top") -- the parents below do not exist yet
		local cache = `{top}/a/b`
		-- umask 0, so only the program's own modes can make the folders private
		local u = zn.run("sh", tracker, cache, { "-c", 'umask 0; exec "$0" list', b })
		t.expect(u.code).toBe(0)
		t.expect(has(u.stdout, "f0001")).toBe(true)
		t.expect(fs.isDir(`{cache}/zn`)).toBe(true)
		-- the parents the program made, and the cache folder, are exactly 0700
		local wrongDirs = sh(`find "{top}/a" -type d ! -perm 700`).stdout
		t.expect(wrongDirs).toBe("")
		local wrongFiles = sh(`find "{cache}/zn" -type f ! -perm 600 ! -perm 700`).stdout
		t.expect(wrongFiles).toBe("")
		local count = sh(`find "{cache}/zn" -type f | wc -l`).stdout
		t.expect((tonumber(count) :: number) > 50).toBe(true) -- it did look at the engine, not at an empty folder
	end)

	it("a symlink in the cache path is refused, naming it, and nothing is written through it", function()
		-- the cache folder itself
		local c = setup("link-cache")
		local marker = `{c.cache}/decoy-ran`
		local real = `{c.cache}/zn-real`
		t.expect(process.exec("mv", { c.zndir, real }).ok).toBe(true)
		t.expect(process.exec("ln", { "-s", real, c.zndir }).ok).toBe(true)
		local before = #fs.readDir(real)
		expectRefused(c, c.zndir, "symbolic link", marker)
		t.expect(#fs.readDir(real)).toBe(before)

		-- the extracted folder, bin, an engine folder, an engine file, the lune: each swapped for a link to a copy
		local cases = { "", "bin", "z-nile/engine", "z-nile/roots.luau", "bin/lune" }
		for i, rel in cases do
			local d = setup(`link-{i}`)
			local target = if rel == "" then d.dir else `{d.dir}/{rel}`
			local m = `{d.cache}/decoy-ran`
			local elsewhere = `{d.cache}/elsewhere-{i}`
			t.expect(process.exec("mv", { target, elsewhere }).ok).toBe(true)
			t.expect(process.exec("ln", { "-s", elsewhere, target }).ok).toBe(true)
			expectRefused(d, target, "symbolic link", m)
		end

		-- a link whose target is a decoy that would leave a marker
		local e = setup("link-decoy")
		local em = `{e.cache}/decoy-ran`
		fs.writeFile(`{e.cache}/decoy`, decoyScript(em))
		process.exec("chmod", { "700", `{e.cache}/decoy` })
		fs.removeFile(e.lune)
		t.expect(process.exec("ln", { "-s", `{e.cache}/decoy`, e.lune }).ok).toBe(true)
		expectRefused(e, e.lune, "symbolic link", em)
	end)

	it("a runtime file with a second hard link is refused, naming it", function()
		local c = setup("hardlink")
		local marker = `{c.cache}/decoy-ran`
		t.expect(process.exec("ln", { c.lune, `{c.cache}/lune-elsewhere` }).ok).toBe(true)
		expectRefused(c, c.lune, "hard link", marker)
		t.expect(fs.isFile(`{c.cache}/lune-elsewhere`)).toBe(true) -- and the other name is not touched
	end)

	it(
		"a folder or runtime file writable by group or others is refused, naming it; one only readable is not",
		function()
			local c = setup("writable")
			local marker = `{c.cache}/decoy-ran`
			local targets = {
				c.zndir,
				c.dir,
				`{c.dir}/bin`,
				c.lune,
				`{c.dir}/z-nile/engine`,
				`{c.dir}/z-nile/engine/main.luau`,
			}
			for _, path in targets do
				for _, mode in { "777", "770", "707" } do
					local mode0 = if fs.isDir(path) then "700" else (if path == c.lune then "700" else "600")
					process.exec("chmod", { mode, path })
					expectRefused(c, path, "writable", marker)
					process.exec("chmod", { mode0, path })
				end
			end
			-- the same cache, every mode put back, runs again
			t.expect(c.run({ "list" }).code).toBe(0)
			-- readable by others is no reason to refuse (the folders are not secret; only writing them matters)
			process.exec("chmod", { "755", c.zndir })
			process.exec("chmod", { "750", `{c.dir}/bin` })
			t.expect(c.run({ "list" }).code).toBe(0)
		end
	)

	it(
		"a relative XDG_CACHE_HOME is ignored; an absolute one the user owns is used; one that is not theirs is not",
		function()
			local b = bin()
			-- relative: the cache goes under HOME/.cache, and nothing is made beside the working folder
			local tracker = zn.tracker("f0427-cache/xdg-rel/tracker")
			local home = zn.fresh("f0427-cache/xdg-rel/home")
			local r = zn.run(
				b,
				tracker,
				"",
				{ "list" },
				{ XDG_CACHE_HOME = "relcache", HOME = home, ZN_CACHE = "" }
			)
			t.expect(r.code).toBe(0)
			t.expect(has(r.stdout, "f0001")).toBe(true)
			t.expect(fs.isDir(`{tracker}/relcache`)).toBe(false)
			t.expect(fs.isDir(`{home}/.cache/zn`)).toBe(true)
			-- "." and a nonexistent absolute folder are ignored the same way
			local home2 = zn.fresh("f0427-cache/xdg-dot/home")
			local tracker2 = zn.tracker("f0427-cache/xdg-dot/tracker")
			local r2 = zn.run(
				b,
				tracker2,
				"",
				{ "list" },
				{ XDG_CACHE_HOME = ".", HOME = home2, ZN_CACHE = "" }
			)
			t.expect(r2.code).toBe(0)
			t.expect(fs.isDir(`{tracker2}/zn`)).toBe(false)
			t.expect(fs.isDir(`{home2}/.cache/zn`)).toBe(true)
			-- absolute and owned: used, and HOME/.cache is not made
			local xdg = zn.fresh("f0427-cache/xdg-abs/xdg")
			local home3 = zn.fresh("f0427-cache/xdg-abs/home")
			local tracker3 = zn.tracker("f0427-cache/xdg-abs/tracker")
			local r3 = zn.run(
				b,
				tracker3,
				"",
				{ "list" },
				{ XDG_CACHE_HOME = xdg, HOME = home3, ZN_CACHE = "" }
			)
			t.expect(r3.code).toBe(0)
			t.expect(fs.isDir(`{xdg}/zn`)).toBe(true)
			t.expect(fs.isDir(`{home3}/.cache`)).toBe(false)
			-- absolute but not the user's (/usr, owned by root): ignored. A root run could not tell, so it fails here.
			t.expect(sh("id -u").stdout ~= "0\n").toBe(true)
			local home4 = zn.fresh("f0427-cache/xdg-foreign/home")
			local tracker4 = zn.tracker("f0427-cache/xdg-foreign/tracker")
			local r4 = zn.run(
				b,
				tracker4,
				"",
				{ "list" },
				{ XDG_CACHE_HOME = "/usr", HOME = home4, ZN_CACHE = "" }
			)
			t.expect(r4.code).toBe(0)
			t.expect(fs.isDir(`{home4}/.cache/zn`)).toBe(true)
			t.expect(fs.isDir("/usr/zn")).toBe(false)
		end
	)

	it("HOME unset, with no ZN_CACHE and no usable XDG_CACHE_HOME, is a message naming HOME", function()
		local b = bin()
		local tracker = zn.tracker("f0427-cache/nohome/tracker")
		local r = zn.run(
			b,
			tracker,
			"",
			{ "list" },
			{ HOME = "", ZN_CACHE = "", XDG_CACHE_HOME = "relative" }
		)
		t.expect(r.code).toBe(1)
		t.expect(has(r.stderr, "HOME")).toBe(true)
		t.expect(has(r.stderr, "ZN_CACHE")).toBe(true)
		t.expect(has(r.stdout, "f0001")).toBe(false)
		-- a relative ZN_CACHE is refused too, naming it
		local rel = zn.run(b, tracker, "", { "list" }, { ZN_CACHE = "cache-here" })
		t.expect(rel.code).toBe(1)
		t.expect(has(rel.stderr, "ZN_CACHE")).toBe(true)
		t.expect(fs.isDir(`{tracker}/cache-here`)).toBe(false)
	end)

	it("the ownership and noexec sentences are checked in the Go tests, not here", function()
		print(
			"NOTE f0427 AC3: a cache folder or runtime file owned by another user (needs root to create) and an exec that "
				.. "fails on a noexec mount (needs a mount) are NOT exercised by this spec. They are checked in "
				.. "z-nile/go/internal/payload/cache_test.go (owner lookup seam) and z-nile/go/cmd/zn/main_test.go (failing exec)."
		)
		t.expect(fs.isFile(`{zn.checkout()}/z-nile/go/internal/payload/cache_test.go`)).toBe(true)
	end)
end)
