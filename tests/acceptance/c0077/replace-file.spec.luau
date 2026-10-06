--!strict
-- c0830: every unjailed writer under .cache replaces whatever is at its path instead of writing through it.
-- scripts/lib/replace-file.pl writes a sibling temporary file (created exclusively, never followed) and renames it
-- onto the path; a rename replaces a link of any kind and refuses a real directory. scripts/check.sh unlinks the
-- links at the top of .cache before it writes there, and the launcher (fence.REAPER) unlinks them after the specs'
-- group is killed, whatever ended it. Every path here is a stand-in under .cache; nothing real is linked to.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local sh = require("@scripts/lib/sh")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0830-replace`
local REPLACE = `{root}/scripts/lib/replace-file.pl`

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

local function isLink(path: string): boolean
	return process.exec("test", { "-L", path }).ok
end

local function link(target: string, path: string)
	t.expect(process.exec("ln", { "-s", target, path }).ok).toBe(true)
end

-- a folder's entries, sorted, as one string
local function listing(dir: string): string
	local names = fs.readDir(dir)
	table.sort(names)
	return table.concat(names, ",")
end

-- leftover temporary files of replace-file in `dir`
local function leftovers(dir: string): { string }
	local out: { string } = {}
	for _, name in fs.readDir(dir) do
		if has(name, ".pickman-tmp.") then
			table.insert(out, name)
		end
	end
	return out
end

local function replace(dest: string, src: string?, stdin: string?): Result
	local args = { REPLACE, dest }
	if src then
		table.insert(args, src)
	end
	return process.exec("perl", args, { stdio = { stdin = stdin or "" } })
end

-- a fresh case folder holding a victim folder with one file, and a victim file
local function case(name: string): (string, string, string)
	local dir = `{base}/{name}`
	fs.writeDir(`{dir}/victim-dir`)
	fs.writeFile(`{dir}/victim-dir/keep`, "keep")
	fs.writeFile(`{dir}/victim-file`, "keep")
	return dir, `{dir}/victim-dir`, `{dir}/victim-file`
end

-- a stand-in checkout for scripts/check.sh: the gate script and its libraries, and stub tools first on PATH
local function gateCopy(name: string): string
	local dir = `{base}/{name}`
	fs.writeDir(`{dir}/scripts/lib`)
	fs.writeFile(`{dir}/scripts/check.sh`, fs.readFile(`{root}/scripts/check.sh`))
	for _, lib in fs.readDir(`{root}/scripts/lib`) do
		if fs.isFile(`{root}/scripts/lib/{lib}`) then
			fs.writeFile(`{dir}/scripts/lib/{lib}`, fs.readFile(`{root}/scripts/lib/{lib}`))
		end
	end
	fs.writeDir(`{dir}/.cache`)
	fs.writeDir(`{dir}/bin`)
	fs.writeDir(`{dir}/home`)
	fs.writeDir(`{dir}/tmp`)
	-- curl: fails when STUB_CURL_FAIL is set, else writes a stand-in definitions file to its -o path
	fs.writeFile(
		`{dir}/bin/curl`,
		'#!/bin/sh\nif [ -n "$STUB_CURL_FAIL" ]; then echo "curl: (22) stub failure" >&2; exit 22; fi\n'
			.. 'o=; while [ $# -gt 0 ]; do [ "$1" = -o ] && o=$2; shift; done; echo "-- stub defs" > "$o"\n'
	)
	-- rojo: fails at once, so the gate stops at its first rojo call, unless STUB_ROJO_OK is set: then it writes its -o
	-- file, and `build` first links .cache/check.rbxl to STUB_VICTIM (so the link is there when the result lands)
	fs.writeFile(
		`{dir}/bin/rojo`,
		'#!/bin/sh\nif [ -z "$STUB_ROJO_OK" ]; then echo "rojo: stub" >&2; exit 1; fi\n'
			.. 'o=; for a; do [ "$prev" = -o ] && o=$a; prev=$a; done\n'
			.. 'if [ "$1" = build ] && [ "$2" = default.project.json ]; then rm -f .cache/check.rbxl; ln -s "$STUB_VICTIM" .cache/check.rbxl; fi\n'
			.. 'echo "built by $1" > "$o"\n'
	)
	-- the other tools pass, and lune fails at the tests stage, which comes after the build
	for _, tool in { "stylua", "selene", "luau-lsp" } do
		fs.writeFile(`{dir}/bin/{tool}`, "#!/bin/sh\nexit 0\n")
	end
	fs.writeFile(
		`{dir}/bin/lune`,
		'#!/bin/sh\ncase "$1" in --version) echo "lune 0.0.0" ;; setup) ;; *) echo "lune: stub" >&2; exit 1 ;; esac\n'
	)
	for _, tool in { "curl", "rojo", "stylua", "selene", "luau-lsp", "lune" } do
		process.exec("chmod", { "+x", `{dir}/bin/{tool}` })
	end
	return dir
end

local function gate(dir: string, env: { [string]: string }?): Result
	local e: { [string]: string } = {
		PATH = `{dir}/bin:{process.env.PATH or ""}`,
		HOME = `{dir}/home`, -- no ~/.rokit/bin in front of the stubs
		TMPDIR = `{dir}/tmp`,
	}
	if env then
		for k, v in env do
			e[k] = v
		end
	end
	return process.exec("bash", { "scripts/check.sh", "--full" }, { cwd = dir, env = e })
end

return t.spec("c0830 writers under .cache never follow a symlink", function(it)
	it("sets up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
	end)

	it(
		"over a link to a directory, the path becomes a regular file and the directory is unchanged",
		function()
			local dir, victimDir = case("dir-link")
			local before = listing(victimDir)
			link(victimDir, `{dir}/target`)
			local r = replace(`{dir}/target`, nil, "fresh")
			t.expect(r.ok).toBe(true)
			t.expect(isLink(`{dir}/target`)).toBe(false)
			t.expect(fs.isFile(`{dir}/target`)).toBe(true)
			t.expect(fs.readFile(`{dir}/target`)).toBe("fresh")
			t.expect(listing(victimDir)).toBe(before)
			t.expect(#leftovers(dir)).toBe(0)
		end
	)

	it("over a link to a file, the path becomes a regular file and the linked file is unchanged", function()
		local dir, _, victimFile = case("file-link")
		link(victimFile, `{dir}/target`)
		local r = replace(`{dir}/target`, nil, "fresh")
		t.expect(r.ok).toBe(true)
		t.expect(isLink(`{dir}/target`)).toBe(false)
		t.expect(fs.readFile(`{dir}/target`)).toBe("fresh")
		t.expect(fs.readFile(victimFile)).toBe("keep")
	end)

	it("a real directory at the path is refused, nothing is written and no temporary file is left", function()
		local dir, victimDir = case("real-dir")
		local before = listing(victimDir)
		local r = replace(victimDir, nil, "fresh")
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "is a directory")).toBe(true)
		t.expect(fs.isDir(victimDir)).toBe(true)
		t.expect(listing(victimDir)).toBe(before)
		t.expect(fs.readFile(`{victimDir}/keep`)).toBe("keep")
		t.expect(#leftovers(dir)).toBe(0)
	end)

	it(
		"content comes from stdin, or from a source file when one is given, and the file is mode 0644",
		function()
			local dir = case("content")
			t.expect(replace(`{dir}/from-stdin`, nil, "piped").ok).toBe(true)
			t.expect(fs.readFile(`{dir}/from-stdin`)).toBe("piped")
			fs.writeFile(`{dir}/src`, "copied")
			t.expect(replace(`{dir}/from-src`, `{dir}/src`, "ignored").ok).toBe(true)
			t.expect(fs.readFile(`{dir}/from-src`)).toBe("copied")
			t.expect(fs.readFile(`{dir}/src`)).toBe("copied") -- the source stays
			for _, name in { "from-stdin", "from-src" } do
				local mode = process.exec("sh", { "-c", 'ls -l "$1" | cut -c1-10', "_", `{dir}/{name}` })
				t.expect((string.gsub(mode.stdout, "%s+$", ""))).toBe("-rw-r--r--")
			end
			t.expect(#leftovers(dir)).toBe(0)
		end
	)

	it("a missing folder fails and leaves no temporary file", function()
		local dir = case("missing")
		local r = replace(`{dir}/no-such-folder/target`, nil, "x")
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "replace-file")).toBe(true)
		t.expect(#leftovers(dir)).toBe(0)
	end)

	it("a source that can't be read fails after the temporary file is made, and leaves none", function()
		local dir = case("unreadable")
		fs.writeFile(`{dir}/target`, "old")
		local r = replace(`{dir}/target`, `{dir}/victim-dir`) -- a folder: it opens, but reading it fails
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "replace-file")).toBe(true)
		t.expect(fs.readFile(`{dir}/target`)).toBe("old")
		t.expect(#leftovers(dir)).toBe(0)
	end)

	it("sh.writeReplacing over a link to a directory leaves the directory unchanged", function()
		local dir, victimDir = case("writer")
		local before = listing(victimDir)
		link(victimDir, `{dir}/tracker-focus`)
		sh.writeReplacing(`{dir}/tracker-focus`, "c0010")
		t.expect(isLink(`{dir}/tracker-focus`)).toBe(false)
		t.expect(fs.readFile(`{dir}/tracker-focus`)).toBe("c0010")
		t.expect(listing(victimDir)).toBe(before)
		-- and a real directory there is an error, not a stray file inside it
		local ok = pcall(sh.writeReplacing, victimDir, "x")
		t.expect(ok).toBe(false)
		t.expect(listing(victimDir)).toBe(before)
	end)

	it(
		"the gate stops with a message when the definitions download fails, leaving no temporary file",
		function()
			local dir = gateCopy("gate-download")
			local r = gate(dir, { STUB_CURL_FAIL = "1" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "globalTypes")).toBe(true)
			t.expect(has(r.stdout .. r.stderr, "rojo: stub")).toBe(false) -- it stopped before the next step
			t.expect(fs.isFile(`{dir}/.cache/globalTypes.d.luau`)).toBe(false)
			t.expect(#leftovers(`{dir}/.cache`)).toBe(0)
			t.expect(#fs.readDir(`{dir}/tmp`)).toBe(0)
		end
	)

	it("the gate removes links at the top of .cache before it writes there", function()
		local dir = gateCopy("gate-links")
		fs.writeDir(`{base}/gate-victim-dir`)
		fs.writeFile(`{base}/gate-victim-dir/keep`, "keep")
		fs.writeFile(`{base}/gate-victim-file`, "-- keep")
		local before = listing(`{base}/gate-victim-dir`)
		link(`{base}/gate-victim-dir`, `{dir}/.cache/check.rbxl`)
		link(`{base}/gate-victim-file`, `{dir}/.cache/globalTypes.d.luau`)
		fs.writeDir(`{dir}/.cache/fixture`)
		link(`{base}/gate-victim-file`, `{dir}/.cache/fixture/deep-link`) -- below the top: not the gate's business
		local r = gate(dir)
		t.expect(r.ok).toBe(false) -- the stub rojo stops it
		t.expect(has(r.stdout .. r.stderr, "rojo: stub")).toBe(true)
		t.expect(isLink(`{dir}/.cache/check.rbxl`)).toBe(false)
		t.expect(fs.isDir(`{dir}/.cache/check.rbxl`)).toBe(false)
		t.expect(isLink(`{dir}/.cache/globalTypes.d.luau`)).toBe(false)
		t.expect(fs.readFile(`{dir}/.cache/globalTypes.d.luau`)).toBe("-- stub defs\n")
		t.expect(fs.readFile(`{base}/gate-victim-file`)).toBe("-- keep")
		t.expect(listing(`{base}/gate-victim-dir`)).toBe(before)
		t.expect(isLink(`{dir}/.cache/fixture/deep-link`)).toBe(true)
		t.expect(#leftovers(`{dir}/.cache`)).toBe(0)
	end)

	it(
		"the build lands as a regular file over a link to a directory, and leaves no build folder behind",
		function()
			local dir = gateCopy("gate-build")
			fs.writeFile(`{dir}/.cache/globalTypes.d.luau`, "-- defs") -- present: no download
			fs.writeDir(`{base}/build-victim`)
			fs.writeFile(`{base}/build-victim/keep`, "keep")
			local before = listing(`{base}/build-victim`)
			local r = gate(dir, { STUB_ROJO_OK = "1", STUB_VICTIM = `{base}/build-victim` })
			t.expect(r.ok).toBe(false) -- the stub lune stops it at the tests stage
			t.expect(has(r.stdout .. r.stderr, "lune: stub")).toBe(true) -- so the build stage ran and passed
			t.expect(isLink(`{dir}/.cache/check.rbxl`)).toBe(false)
			t.expect(fs.readFile(`{dir}/.cache/check.rbxl`)).toBe("built by build\n")
			t.expect(listing(`{base}/build-victim`)).toBe(before)
			t.expect(#fs.readDir(`{dir}/tmp`)).toBe(0) -- the build folder is gone
			t.expect(#leftovers(`{dir}/.cache`)).toBe(0)
		end
	)
	local function reap(cache: string, script: string): Result
		return process.exec(
			"perl",
			{ "-e", fence.REAPER, "sh", "-c", script, "_", cache },
			{ env = { PICKMAN_REAP_CACHE = cache } }
		)
	end

	local function reapCase(name: string): (string, string)
		local cache = `{base}/{name}`
		fs.writeDir(`{cache}/sub`)
		fs.writeFile(`{cache}/plain`, "keep")
		fs.writeFile(`{base}/{name}-victim`, "keep")
		link(`{base}/{name}-victim`, `{cache}/sub/deep-link`)
		return cache, `{base}/{name}-victim`
	end

	it(
		"after the command ends the launcher unlinks links at the top of the cache it was given, and nothing else",
		function()
			local cache, victim = reapCase("reap")
			local r =
				reap(cache, 'ln -s "$1/sub" "$1/swapped-dir" && ln -s /nonexistent "$1/swapped-file"; exit 3')
			t.expect(r.code).toBe(3) -- the command's status still passes through
			t.expect(isLink(`{cache}/swapped-dir`)).toBe(false)
			t.expect(isLink(`{cache}/swapped-file`)).toBe(false)
			t.expect(fs.readFile(`{cache}/plain`)).toBe("keep")
			t.expect(fs.isDir(`{cache}/sub`)).toBe(true)
			t.expect(isLink(`{cache}/sub/deep-link`)).toBe(true)
			t.expect(fs.readFile(victim)).toBe("keep")
		end
	)

	it("the launcher unlinks them even when the command was killed by a signal", function()
		local cache = reapCase("reap-signal")
		local r = reap(cache, 'ln -s "$1/sub" "$1/swapped"; kill -KILL $$')
		t.expect(r.ok).toBe(false)
		t.expect(isLink(`{cache}/swapped`)).toBe(false)
		t.expect(fs.isDir(`{cache}/sub`)).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
