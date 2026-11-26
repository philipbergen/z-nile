--!strict
-- f0427: building zn for the specs. Every build goes through z-nile/lib/znbuild.sh into a folder under this home's
-- .cache/zn-test, in a copy of z-nile/go (the build writes the embedded files into the module), with Go's caches under
-- .cache too. Nothing outside .cache is written, and nothing is downloaded.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")

local zn = {}

export type Built = { ok: boolean, code: number, stderr: string, stdout: string, bin: string, godir: string }

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

-- The checkout's top (the spec runs inside it).
function zn.checkout(): string
	return trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
end

-- This home's physical path.
function zn.home(): string
	return fixture.physical(".") :: string
end

-- A fresh folder .cache/<name> under this home.
function zn.fresh(name: string): string
	local dir = `{zn.home()}/.cache/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	return dir
end

-- A fixture HOME under .cache, made once: nothing of the developer's home (rokit, ~/.cache) is reachable through it.
function zn.fixtureHome(): string
	local dir = `{zn.home()}/.cache/f0427-embed/home`
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	return dir
end

-- This machine's names: Go's goos and goarch, and lune.sum's platform key.
function zn.host(): (string, string, string)
	local goos = if process.os == "macos" then "darwin" else process.os
	local goarch = if process.arch == "aarch64" then "arm64" else "amd64"
	return goos, goarch, `{goos}-{if goarch == "arm64" then "aarch64" else "x86_64"}`
end

-- The entry of the real z-nile/go/cmd/zn/lune.sum for a platform: kind and digest.
function zn.pin(platform: string): (string, string)
	local text = fs.readFile(`{zn.checkout()}/z-nile/go/cmd/zn/lune.sum`)
	for line in string.gmatch(text, "[^\n]+") do
		local kind, plat, sha = string.match(line, "^(%a+) (%S+) (%x+) ")
		if plat == platform and kind and sha then
			return kind, sha
		end
	end
	error(`lune.sum has no entry for {platform}`, 2)
end

-- The Lune a host build takes: the CI zip when ZN_TEST_LUNE_ZIP names one, else (macOS arm64) the one rokit installed,
-- named explicitly because the builds run under a fixture HOME.
function zn.hostLuneArgs(): { string }
	local zip = process.env.ZN_TEST_LUNE_ZIP
	if zip and zip ~= "" then
		return { "--lune-zip", zip }
	end
	local _, _, platform = zn.host()
	local home = process.env.HOME
	if platform == "darwin-aarch64" and home then
		return { "--lune", `{home}/.rokit/tool-storage/lune-org/lune/0.10.5/lune` }
	end
	return {}
end

-- Builds zn into .cache/zn-test/<label>/zn. `args` are znbuild.sh's (--goos, --lune-zip, --sum, ...). The Go module is a
-- copy of this checkout's, so the embedded files land in the copy.
function zn.build(label: string, args: { string }, checkoutOverride: string?): Built
	local here = zn.checkout() -- the scripts and the Go module come from here
	local checkout = checkoutOverride or here
	local dir = zn.fresh(`zn-test/{label}`)
	local godir = `{dir}/go`
	local cp = process.exec("cp", { "-R", `{here}/z-nile/go`, godir })
	if not cp.ok then
		error(`cp of z-nile/go failed: {cp.stderr}`, 2)
	end
	process.exec("rm", { "-rf", `{godir}/internal/payload/embedded` })
	local argv =
		{ `{here}/z-nile/lib/znbuild.sh`, "--out", `{dir}/zn`, "--go-dir", godir, "--checkout", checkout }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("bash", argv, {
		env = {
			HOME = zn.fixtureHome(), -- the real one (and its rokit tools) is out of reach; the Lune is passed explicitly
			GOCACHE = `{zn.home()}/.cache/zn-test/go-build`,
			GOPATH = `{zn.home()}/.cache/zn-test/gopath`,
			GOFLAGS = "-modcacherw",
			GOTELEMETRY = "off",
			GIT_OPTIONAL_LOCKS = "0",
		},
	})
	return { ok = r.ok, code = r.code, stderr = r.stderr, stdout = r.stdout, bin = `{dir}/zn`, godir = godir }
end

-- A tracker-shaped fixture checkout with one ticket, f0001, and nothing else: the engine's `list` finds it.
function zn.tracker(name: string): string
	local dir = zn.fresh(name)
	fs.writeDir(`{dir}/z-nile`)
	fs.writeDir(`{dir}/demo/.tracker/issues/f0001`)
	fs.writeDir(`{dir}/demo/.tracker/rafts`)
	fs.writeFile(`{dir}/z-nile/projects.toml`, '[[project]]\nname = "demo"\nroot = "demo/.tracker"\n')
	fs.writeFile(`{dir}/z-nile/next`, "issue 1 aa-bb-cc\nraft 0 aa-bb-cc\n")
	fs.writeFile(
		`{dir}/demo/.tracker/issues/f0001/f0001.md`,
		"---\nid: f0001\ntype: feature\ntitle: Hello fixture\nslug: hello-fixture\nraft: \ndepends_on: []\nemergent: false\ndesign: none\nrisk: normal\ncreated: 2026-11-21\nstatus: new-aa-bb-cc\n---\n\n# f0001: Hello fixture\n\n## Problem\n- a fixture ticket\n"
	)
	local init = process.exec("git", { "init", "-q", "-b", "main", dir })
	if not init.ok then
		error(`git init of {dir} failed: {init.stderr}`, 2)
	end
	fixture.git(dir, { "add", "-A" })
	fixture.git(
		dir,
		{ "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-qm", "fixture" }
	)
	return dir
end

-- The PATH a built zn runs under: the system's /usr/bin:/bin, with the runner's browser guard (its recording `open` and
-- `xdg-open` stubs) first when the run has one. The guard folder holds no lune, so "no Lune on PATH" still holds.
function zn.path(): string
	local guard = process.env.PICKMAN_OPEN_GUARD
	if guard and guard ~= "" and fs.isFile(`{guard}/open`) then
		return `{guard}:/usr/bin:/bin`
	end
	-- never a PATH that reaches the real open: a run without the runner's guard fails here
	error("PICKMAN_OPEN_GUARD is not set or has no open stub: run this spec through tests/run", 2)
end

-- What the runner's browser guard recorded so far ("" when nothing opened, or when there is no guard).
function zn.opened(): string
	local guard = process.env.PICKMAN_OPEN_GUARD
	if guard and fs.isFile(`{guard}/opened.log`) then
		return fs.readFile(`{guard}/opened.log`)
	end
	return ""
end

-- Go must be there: without it the cases cannot run, and a spec that passed having run nothing would be a false green.
function zn.needGo(): boolean
	if process.exec("sh", { "-c", "command -v go" }).ok then
		return true
	end
	error("Go 1.24 or newer is needed to build zn (SETUP.md): this spec cannot pass without it", 2)
end

-- Runs a built zn in a fixture checkout with no Lune on PATH, its cache in a throwaway folder, a fixture HOME and no
-- ZN_TOP or ZN_CWD from the caller. `extra` adds or replaces environment (PATH included).
function zn.run(
	bin: string,
	dir: string,
	cache: string,
	args: { string },
	extra: { [string]: string }?
): fixture.Result
	local env: { [string]: string } = {
		PATH = zn.path(),
		ZN_CACHE = cache,
		XDG_CACHE_HOME = "", -- a wrong implementation must never reach the caller's real cache
		ZN_TOP = "",
		ZN_CWD = "",
		HOME = zn.fixtureHome(),
		GIT_OPTIONAL_LOCKS = "0",
	}
	if extra then
		for k, v in extra do
			env[k] = v
		end
	end
	-- every zn runs under a 60 s alarm, so a hang fails fast
	local bounded = { "-e", "alarm 60; exec @ARGV", bin }
	for _, a in args do
		table.insert(bounded, a)
	end
	return fixture.exec(dir, "perl", bounded, { env = env })
end

return zn
