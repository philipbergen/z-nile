--!strict
-- R0070 review 001 on c0194 (temporary trees under .cache/.tmp): the cases the sequestered c0194 specs do not pin.
-- F3 leftovers on a linked temp folder, F4 what the stale sweep removes, F5 deploy-beta removes its tree, F6 and F7 the
-- jail command line.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local tmp = require("@znile/lib/tmp")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/r0070-tmp-review`
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local CLI = `{root}/z-nile/lib/tmpcli`

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

local function fresh(name: string): string
	local dir = `{base}/{name}`
	if fs.isDir(dir) then
		must(process.exec("rm", { "-rf", dir }), "rm")
	end
	fs.writeDir(dir)
	return dir
end

local function checkout(name: string): string
	local dir = fresh(name)
	fs.writeDir(`{dir}/.cache`)
	return dir
end

-- sets the modification time of the paths `seconds` into the past
local function ago(seconds: number, ...: string)
	must(
		process.exec("perl", {
			"-e",
			"my $t = time - shift; utime($t, $t, @ARGV) == @ARGV or exit 1",
			tostring(seconds),
			...,
		}),
		"utime"
	)
end

local DAY = 86400

local function probes(busy: { string }?): tmp.Probes
	return {
		workingDirs = function()
			return busy
		end,
		startOf = function(_pid: string)
			return ""
		end,
	}
end

local function stubs(name: string, files: { [string]: string }): string
	local dir = fresh(name)
	for file, text in files do
		fs.writeFile(`{dir}/{file}`, text)
		must(process.exec("chmod", { "+x", `{dir}/{file}` }), "chmod")
	end
	return dir
end

return t.spec("R0070 review 001 of c0194", function(it)
	-- ---------------------------------------------------------------------------------------------- F3 leftovers
	-- the user temp folder is /var/folders/..., a link to /private/var/..., and lsof and pwd -P speak the physical one
	it("leftovers reached through a link removes a named tree and reports it", function()
		local dir = fresh("lf-link")
		fs.writeDir(`{dir}/real/tmp.AAA`)
		fs.writeDir(`{dir}/real/tmp.BBB`)
		must(process.exec("ln", { "-s", `{dir}/real`, `{dir}/link` }), "ln")
		local lines = tmp.leftovers({ "tmp.AAA" }, `{dir}/link`, probes({}))
		t.expect(fs.isDir(`{dir}/real/tmp.AAA`)).toBe(false)
		t.expect(fs.isDir(`{dir}/real/tmp.BBB`)).toBe(true)
		local joined = table.concat(lines, "\n")
		t.expect(has(joined, "tmp.AAA\t") and has(joined, "REMOVED")).toBe(true)
	end)

	it("a tree a process works in, listed by its physical path, is IN USE and kept although named", function()
		local dir = fresh("lf-busy")
		fs.writeDir(`{dir}/real/tmp.AAA`)
		fs.writeDir(`{dir}/real/tmp.BBB`)
		must(process.exec("ln", { "-s", `{dir}/real`, `{dir}/link` }), "ln")
		local lines =
			tmp.leftovers({ "tmp.AAA", "tmp.BBB" }, `{dir}/link`, probes({ `{dir}/real/tmp.BBB/sub` }))
		t.expect(fs.isDir(`{dir}/real/tmp.BBB`)).toBe(true)
		t.expect(fs.isDir(`{dir}/real/tmp.AAA`)).toBe(false)
		for _, line in lines do
			if has(line, "tmp.BBB\t") then
				t.expect(has(line, "IN USE")).toBe(true)
			end
		end
	end)

	it("leftovers that cannot tell what is in use removes nothing and says IN USE?", function()
		local dir = fresh("lf-blind")
		fs.writeDir(`{dir}/tmp.AAA`)
		local lines = tmp.leftovers({ "tmp.AAA" }, dir, probes(nil))
		t.expect(fs.isDir(`{dir}/tmp.AAA`)).toBe(true)
		t.expect(#lines).toBe(1)
		t.expect(has(lines[1] :: string, "IN USE?")).toBe(true)
	end)

	it("leftovers of a folder that is not one lists nothing and says why", function()
		local lines, why = tmp.leftovers({}, `{base}/no-such-folder`, probes({}))
		t.expect(#lines).toBe(0)
		t.expect(has(why or "", "is not a folder")).toBe(true)
	end)

	-- ------------------------------------------------------------------------------------------------ final review F1, F2
	-- a PATH that holds lune, the basic tools and no lsof (a Linux without it; macOS keeps lsof in /usr/sbin)
	local function blindPath(name: string): string
		local bin = `{fresh(name)}/bin`
		fs.writeDir(bin)
		must(
			process.exec("sh", {
				"-c",
				'for f in "$1"/* /usr/bin/* /bin/*; do n=${f##*/}; [ "$n" = lsof ] || [ -e "$2/$n" ] || ln -s "$f" "$2/$n"; done',
				"_",
				trim(process.exec("sh", { "-c", 'dirname "$(command -v lune)"' }).stdout),
				bin,
			}),
			"tools"
		)
		return bin
	end

	it("a sweep where lsof cannot be started says so in one line and keeps every tree", function()
		local co = checkout("no-lsof-sweep")
		local r0 = tmp.root(co) :: string
		fs.writeDir(`{r0}/aaa.A`)
		ago(4 * DAY, `{r0}/aaa.A`)
		local r = process.exec("lune", { "run", CLI, "--", "sweep", "--dir", co }, {
			env = {
				PATH = blindPath("no-lsof-bin-1"),
				HOME = process.env.HOME or "",
				TMPDIR = process.env.TMPDIR or "",
			},
		})
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "lsof")).toBe(true)
		t.expect(has(r.stderr, "Stack Begin")).toBe(false)
		t.expect(fs.isDir(`{r0}/aaa.A`)).toBe(true)
	end)

	it("leftovers where lsof cannot be started lists every tree as IN USE? and removes none", function()
		local dir = fresh("no-lsof-leftovers")
		fs.writeDir(`{dir}/tmp.AAA`)
		local script = `{dir}/probe.luau`
		fs.writeFile(
			script,
			'local tmp = require("@znile/lib/tmp")\nlocal lines = tmp.leftovers({ "tmp.AAA" }, "'
				.. dir
				.. '", tmp.REAL)\nprint(lines[1])\n'
		)
		local r = process.exec("lune", { "run", script }, {
			env = {
				PATH = blindPath("no-lsof-bin-2"),
				HOME = process.env.HOME or "",
				TMPDIR = process.env.TMPDIR or "",
			},
		})
		t.expect(has(r.stdout .. r.stderr, "IN USE?")).toBe(true)
		t.expect(fs.isDir(`{dir}/tmp.AAA`)).toBe(true)
	end)

	it("a FIFO inside an aged tree makes the sweep neither panic nor keep the tree", function()
		local co = checkout("fifo-inside")
		local r0 = tmp.root(co) :: string
		fs.writeDir(`{r0}/aaa.A`)
		must(process.exec("mkfifo", { `{r0}/aaa.A/pipe` }), "mkfifo")
		ago(4 * DAY, `{r0}/aaa.A`, `{r0}/aaa.A/pipe`)
		local r = process.exec("lune", { "run", CLI, "--", "sweep", "--dry-run", "--dir", co })
		t.expect(has(r.stderr, "panicked")).toBe(false)
		t.expect(has(r.stderr, "would remove")).toBe(true)
	end)

	-- ------------------------------------------------------------------------------------------------ F4 sweep
	it("the sweep removes a plain file left two days and keeps a FIFO", function()
		local co = checkout("sweep-kinds")
		local r0 = tmp.root(co) :: string
		fs.writeFile(`{r0}/tmp.FILE`, "x")
		must(process.exec("mkfifo", { `{r0}/pipe.A` }), "mkfifo")
		ago(2 * DAY, `{r0}/tmp.FILE`, `{r0}/pipe.A`)
		local found = tmp.sweep(co, false, probes({})) :: { string }
		t.expect(#found).toBe(1)
		t.expect(fs.isFile(`{r0}/tmp.FILE`)).toBe(false)
		t.expect(process.exec("test", { "-p", `{r0}/pipe.A` }).ok).toBe(true)
	end)

	it("a tree whose owner record cannot be read is judged by the day rule", function()
		local co = checkout("sweep-garbled")
		local r0 = tmp.root(co) :: string
		for _, n in { "young.A", "old.A" } do
			fs.writeDir(`{r0}/{n}`)
			fs.writeFile(`{r0}/{n}/.pickman-owner`, "not a record\n")
		end
		ago(2 * 3600, `{r0}/young.A/.pickman-owner`, `{r0}/young.A`)
		ago(2 * DAY, `{r0}/old.A/.pickman-owner`, `{r0}/old.A`)
		tmp.sweep(co, false, probes({}))
		t.expect(fs.isDir(`{r0}/young.A`)).toBe(true)
		t.expect(fs.isDir(`{r0}/old.A`)).toBe(false)
	end)

	-- ------------------------------------------------------------------------------------------- F5 deploy-beta
	local function deploy(
		name: string,
		projectFile: boolean,
		rojo: string,
		extra: { [string]: string }?
	): (Result, string)
		local home = fresh(name)
		if projectFile then
			fs.writeFile(`{home}/default.project.json`, '{"name":"x","tree":{"$className":"DataModel"}}')
		end
		local bin = stubs(`{name}-bin`, { rojo = rojo })
		-- the spec run's own TMPDIR is inherited otherwise, and the tree would go there
		local folder = tmp.root(home) :: string
		local env = {
			TMPDIR = folder,
			PATH = `{bin}:{process.env.PATH or ""}`,
			HOME = process.env.HOME or "",
			ROBLOX_API_KEY = "k",
			ROBLOX_BETA_UNIVERSE_ID = "1",
			ROBLOX_BETA_PLACE_ID = "2",
		}
		if extra then
			for k, v in extra do
				env[k] = v
			end
		end
		local r = process.exec(
			"lune",
			{ "run", `{root}/pickman/scripts/deploy-beta` },
			{ cwd = home, env = env }
		)
		return r, folder
	end

	local function treesIn(folder: string): { string }
		local out = {}
		if fs.isDir(folder) then
			for _, n in fs.readDir(folder) do
				if string.sub(n, 1, 12) == "deploy-beta." then
					table.insert(out, n)
				end
			end
		end
		return out
	end

	it("deploy-beta leaves no tree after a failed build", function()
		local r, folder = deploy("deploy-fail", true, "#!/bin/sh\necho no >&2\nexit 1\n")
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "rojo build failed")).toBe(true)
		t.expect(#treesIn(folder)).toBe(0)
	end)

	it("deploy-beta leaves no tree when the project file is missing", function()
		local r, folder = deploy("deploy-missing", false, "#!/bin/sh\nexit 0\n")
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "the project file is missing")).toBe(true)
		t.expect(#treesIn(folder)).toBe(0)
	end)

	it("deploy-beta leaves no tree after a publish that fails", function()
		-- the build succeeds; the publish goes to a loopback port nothing listens on and fails
		local r, folder = deploy(
			"deploy-publish",
			true,
			'#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done\necho place > "$out"\n',
			{ OPENCLOUD_BASE = "http://127.0.0.1:1" }
		)
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout, "rojo build failed")).toBe(false)
		t.expect(#treesIn(folder)).toBe(0)
	end)

	-- ------------------------------------------------------------------------------------------ F6, F7 the jail
	local function jailRun(name: string, args: { string }): (Result, number)
		local co = checkout(name)
		local tree = tmp.new(co, "unguarded", nil) :: string
		local bin = stubs(`{name}-bin`, {
			["sandbox-exec"] = `#!/bin/sh\n[ "$1" = -p ] || exit 97\nshift 2\nexec "$@"\n`,
		})
		local env = { PATH = `{bin}:{process.env.PATH or ""}`, HOME = process.env.HOME or "" }
		local argv = { "run", CLI, "--", "jail" }
		for _, a in args do
			table.insert(argv, if a == "TREE" then tree else a)
		end
		local started = os.clock()
		local r = process.exec("lune", argv, { env = env })
		return r, os.clock() - started
	end

	it("jail --time stops a command at the limit with 124", function()
		local r, took = jailRun("jail-time", { "--time", "1", "TREE", "--", "sleep", "20" })
		t.expect(r.code).toBe(124)
		t.expect(took < 15).toBe(true)
	end)

	it("jail still passes a quick command's own exit code on, and refuses a bad limit", function()
		local r = jailRun("jail-quick", { "--time", "30", "TREE", "--", "sh", "-c", "exit 5" })
		t.expect(r.code).toBe(5)
		for _, bad in { "0", "3601", "x", "1.5" } do
			local refused = jailRun("jail-bad", { "--time", bad, "TREE", "--", "true" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "tmp: --time")).toBe(true)
		end
	end)

	it("jail leaves the command's own --dir, --dry-run and --owner alone", function()
		local r = jailRun(
			"jail-args",
			{ "TREE", "--", "sh", "-c", 'echo "$@"', "_", "--dir", "x", "--dry-run", "--owner", "1" }
		)
		t.expect(r.ok).toBe(true)
		t.expect(trim(r.stdout)).toBe("--dir x --dry-run --owner 1")
	end)
end)
