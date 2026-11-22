--!strict
-- f0427 AC1 (and AC2's job on ubuntu): zn carries its Lune and engine, so it runs with no Lune on PATH, from the payload
-- and not from the checkout; the linux build is an ELF holding the Lune that lune.sum pins; a build with no pinned Lune,
-- or none supplied, or one that does not match fails with a message. Builds go through znbuild.sh into .cache/zn-test;
-- fixtures live under .cache/f0427-embed. Every zn runs with a fixture HOME, so ~/.rokit cannot be reached.
-- Lune for the host build: on macOS arm64 the one rokit installed (passed explicitly); on linux the release zip named by
-- ZN_TEST_LUNE_ZIP (the CI workflow downloads and checks it). Nothing is downloaded here.
-- The runner has no skipped state: a case that cannot run here prints a SKIPPED line and is counted as passed.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local zn = require("./lib/zn")

local zipEnv = process.env.ZN_TEST_LUNE_ZIP
local PROBE = "f0427-probe-from-payload"
-- the six paths the engine tar carries (Design section 1)
local PATHS = {
	"z-nile/engine",
	"z-nile/lib",
	"z-nile/vendor",
	"z-nile/templates",
	"z-nile/roots.luau",
	"z-nile/affected.luau",
}

local function mtime(path: string): number
	local at = fs.metadata(path).modifiedAt
	return if at then at.unixTimestampMillis else 0
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function sha(bytes: string): string
	return serde.hash("sha256", bytes)
end

-- Every regular file under dir, as paths relative to it.
local function walk(dir: string, rel: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			walk(path, `{rel}{name}/`, out)
		else
			table.insert(out, `{rel}{name}`)
		end
	end
end

-- The files git tracks under the six paths of `checkout`, read at the edge.
local function tracked(checkout: string): { string }
	local r = process.exec("git", { "ls-files", "-z", "--", table.unpack(PATHS) }, { cwd = checkout })
	if not r.ok then
		error(`git ls-files failed: {r.stderr}`, 2)
	end
	local out = {}
	for name in string.gmatch(r.stdout, "[^\0]+") do
		table.insert(out, name)
	end
	return out
end

-- A throwaway checkout holding a commit of the tracked engine files, with a probe line added to main.luau that prints
-- PROBE when F0427_PROBE is "1". zn built from it must run that copy, not the real checkout's engine.
local function probeCheckout(): (string, { [string]: string })
	local src = zn.fresh("f0427-embed/src")
	local files = tracked(zn.checkout())
	local want: { [string]: string } = {}
	for _, name in files do
		local dir = string.match(name, "^(.*)/[^/]+$") :: string
		fs.writeDir(`{src}/{dir}`)
		local cp = process.exec("cp", { "-p", `{zn.checkout()}/{name}`, `{src}/{name}` })
		if not cp.ok then
			error(`cp {name} failed: {cp.stderr}`, 2)
		end
	end
	local main = fs.readFile(`{src}/z-nile/engine/main.luau`)
	local first, rest = string.match(main, "^([^\n]*\n)(.*)$")
	main =
		`{first}do local p = require("@lune/process"); if p.env.F0427_PROBE == "1" then print("{PROBE}") end end\n{rest}`
	fs.writeFile(`{src}/z-nile/engine/main.luau`, main)
	for _, name in files do
		want[name] = fs.readFile(`{src}/{name}`)
	end
	local init = process.exec("git", { "init", "-q", "-b", "main", src })
	if not init.ok then
		error(`git init failed: {init.stderr}`, 2)
	end
	local add = process.exec("git", { "-C", src, "add", "-A" })
	local commit = process.exec("git", {
		"-C",
		src,
		"-c",
		"user.name=t",
		"-c",
		"user.email=t@example.invalid",
		"commit",
		"-qm",
		"probe",
	})
	if not add.ok or not commit.ok then
		error(`git add/commit failed: {add.stderr}{commit.stderr}`, 2)
	end
	return src, want
end

local hostBuilt: zn.Built? = nil

return t.spec("f0427 zn embeds its Lune and engine", function(it)
	it("with PATH stripped of lune, zn runs the engine it carries, extracted once and verified", function()
		if not zn.needGo() then
			return
		end
		t.expect(process.exec("sh", { "-c", `PATH={zn.path()} command -v lune` }).ok).toBe(false)
		local src, want = probeCheckout()
		local built = zn.build("host", zn.hostLuneArgs(), src)
		fs.removeDir(src) -- the checkout the engine came from no longer exists: only the payload can supply it
		if not built.ok then
			error(`host build failed ({built.code}): {built.stderr}`, 2)
		end
		hostBuilt = built
		local goos, goarch, platform = zn.host()
		local dir = zn.tracker("f0427-embed/tracker")
		local cache = zn.fresh("f0427-embed/cache") -- fresh in this run: the extraction below is a cold one
		local l = zn.run(built.bin, dir, cache, { "list" }, { F0427_PROBE = "1" })
		t.expect(l.code).toBe(0)
		t.expect(has(l.stdout, "f0001")).toBe(true)
		t.expect(has(l.stdout, PROBE)).toBe(true) -- the engine that ran is the one packed from the throwaway checkout
		local b = zn.run(built.bin, dir, cache, { "board", "-O" })
		t.expect(b.code).toBe(0)
		t.expect(fs.isFile(`{dir}/.cache/board.html`)).toBe(true)
		t.expect(zn.opened()).toBe("") -- nothing reached open or xdg-open

		-- version: the id, and the Lune's digest and pin kind, which are the real lune.sum's for this platform
		local v = zn.run(built.bin, dir, cache, { "version" })
		t.expect(v.code).toBe(0)
		t.expect(string.sub(v.stdout, 1, 3)).toBe("zn ")
		t.expect(has(v.stdout, `{goos}/{goarch}`)).toBe(true)
		local id = string.match(v.stdout, "payload (%x+)")
		local luneSum, kind = string.match(v.stdout, "lune (%x+) %((%a+) pin%)")
		t.expect(id ~= nil and luneSum ~= nil).toBe(true)
		local pinKind, pinSha = zn.pin(platform)
		t.expect(kind).toBe(pinKind)
		local lune = `{cache}/zn/{id}/bin/lune`
		t.expect(luneSum).toBe(string.sub(sha(fs.readFile(lune)), 1, 16)) -- the digest of the Lune zn extracted
		if pinKind == "bin" then
			t.expect(luneSum).toBe(string.sub(pinSha, 1, 16)) -- and it is the pinned one
		else
			t.expect(zipEnv ~= nil and zipEnv ~= "").toBe(true)
			local out = zn.fresh("f0427-embed/zip-lune")
			t.expect(process.exec("sh", { "-c", `unzip -p "{zipEnv}" lune > "{out}/lune"` }).ok).toBe(true)
			t.expect(luneSum).toBe(string.sub(sha(fs.readFile(`{out}/lune`)), 1, 16))
		end

		-- the whole engine is there: every tracked file of the six paths, byte for byte, and nothing more under z-nile
		local base = `{cache}/zn/{id}`
		local count = 0
		for name, bytes in want do
			t.expect(fs.isFile(`{base}/{name}`)).toBe(true)
			t.expect(fs.readFile(`{base}/{name}`) == bytes).toBe(true)
			count += 1
		end
		local found: { string } = {}
		walk(`{base}/z-nile`, "", found)
		t.expect(#found).toBe(count)

		-- extracted once: one folder named by the content id, no leftovers, and later runs leave the Lune as it was,
		-- even where nothing may be written beside it (a run that extracts again cannot succeed there)
		local names = fs.readDir(`{cache}/zn`)
		t.expect(#names).toBe(1)
		t.expect(names[1]).toBe(id)
		local before = mtime(lune)
		t.expect(fs.isFile(lune) and before > 0).toBe(true)
		local readonly = process.exec("chmod", { "0500", `{cache}/zn` })
		t.expect(readonly.ok).toBe(true)
		local ok, second = pcall(zn.run, built.bin, dir, cache, { "list" })
		process.exec("chmod", { "0700", `{cache}/zn` })
		if not ok then
			error(second, 0)
		end
		t.expect((second :: any).code).toBe(0)
		t.expect(mtime(lune)).toBe(before)
		t.expect(#fs.readDir(`{cache}/zn`)).toBe(1)
	end)

	it("a lune on PATH is never run: the extracted one comes first", function()
		if not zn.needGo() then
			return
		end
		local built = hostBuilt
		if not built then
			error("the first case did not build the host zn", 2)
		end
		local decoy = zn.fresh("f0427-embed/decoy")
		local marker = `{decoy}/was-run`
		fs.writeFile(`{decoy}/lune`, `#!/bin/sh\ntouch "{marker}"\nexit 97\n`)
		process.exec("chmod", { "+x", `{decoy}/lune` })
		local dir = zn.tracker("f0427-embed/decoy-tracker")
		local cache = zn.fresh("f0427-embed/decoy-cache")
		local r = zn.run(built.bin, dir, cache, { "list" }, { PATH = `{decoy}:{zn.path()}` })
		t.expect(r.code).toBe(0)
		t.expect(has(r.stdout, "f0001")).toBe(true)
		t.expect(fs.isFile(marker)).toBe(false)
	end)

	it("the linux/amd64 build is an ELF whose payload holds the Lune a sum pins and the engine", function()
		if not zn.needGo() then
			return
		end
		local dir = zn.fresh("f0427-embed/fake")
		local marker = "FAKE-LUNE-f0427-marker"
		fs.writeFile(`{dir}/lune`, marker)
		fs.writeFile(`{dir}/lune.sum`, `bin linux-x86_64 {sha(marker)} lune\n`)
		local built = zn.build(
			"linux-fixture",
			{ "--goos", "linux", "--goarch", "amd64", "--lune", `{dir}/lune`, "--sum", `{dir}/lune.sum` }
		)
		if not built.ok then
			error(`linux build failed ({built.code}): {built.stderr}`, 2)
		end
		local elf = fs.readFile(built.bin)
		t.expect(string.sub(elf, 1, 4)).toBe("\127ELF")
		t.expect(has(elf, marker)).toBe(true)
		t.expect(has(elf, "z-nile/engine/main.luau")).toBe(true)
	end)

	it(
		"with the real pinned linux Lune (the zip) the linux build embeds exactly the Lune lune.sum pins",
		function()
			if not zn.needGo() then
				return
			end
			if not zipEnv or zipEnv == "" then
				if process.env.GITHUB_ACTIONS == "true" then
					error(
						"ZN_TEST_LUNE_ZIP is unset on CI: the workflow must download the pinned zip, never skip this case",
						2
					)
				end
				print(
					"SKIPPED real linux zip: ZN_TEST_LUNE_ZIP unset. NOT proven here, though the runner counts this case as passed; the pinned linux Lune is checked by zn-linux.yml (AC2)"
				)
				return
			end
			local kind, pinSha = zn.pin("linux-x86_64")
			t.expect(kind).toBe("zip")
			t.expect(sha(fs.readFile(zipEnv))).toBe(pinSha) -- the zip is the one lune.sum pins
			local out = zn.fresh("f0427-embed/real-zip")
			t.expect(process.exec("sh", { "-c", `unzip -p "{zipEnv}" lune > "{out}/lune"` }).ok).toBe(true)
			local luneBytes = fs.readFile(`{out}/lune`)
			t.expect(#luneBytes > 1000000).toBe(true)
			t.expect(string.sub(luneBytes, 1, 4)).toBe("\127ELF")
			local built =
				zn.build("linux-real", { "--goos", "linux", "--goarch", "amd64", "--lune-zip", zipEnv })
			if not built.ok then
				error(`linux build failed ({built.code}): {built.stderr}`, 2)
			end
			local elf = fs.readFile(built.bin)
			t.expect(string.sub(elf, 1, 4)).toBe("\127ELF")
			t.expect(has(elf, luneBytes)).toBe(true)
		end
	)

	it("a build with no Lune supplied, or one that does not match lune.sum, fails with a message", function()
		if not zn.needGo() then
			return
		end
		local none = zn.build("linux-none", { "--goos", "linux", "--goarch", "amd64" })
		t.expect(none.ok).toBe(false)
		t.expect(has(none.stderr, "no Lune supplied for linux-x86_64")).toBe(true)
		t.expect(fs.isFile(none.bin)).toBe(false)
		local dir = zn.fresh("f0427-embed/wrong")
		fs.writeFile(`{dir}/not-the-zip`, "not the pinned zip")
		local wrong = zn.build(
			"linux-wrong",
			{ "--goos", "linux", "--goarch", "amd64", "--lune-zip", `{dir}/not-the-zip` }
		)
		t.expect(wrong.ok).toBe(false)
		t.expect(has(wrong.stderr, "does not match lune.sum")).toBe(true)
		t.expect(fs.isFile(wrong.bin)).toBe(false)
		-- a bin pin is checked too: a fixture sum pins another digest than the file supplied
		fs.writeFile(`{dir}/lune`, "a lune binary")
		fs.writeFile(`{dir}/lune.sum`, `bin linux-x86_64 {sha("another binary")} lune\n`)
		local bin = zn.build(
			"linux-bin-wrong",
			{ "--goos", "linux", "--goarch", "amd64", "--lune", `{dir}/lune`, "--sum", `{dir}/lune.sum` }
		)
		t.expect(bin.ok).toBe(false)
		t.expect(has(bin.stderr, "does not match lune.sum")).toBe(true)
		t.expect(fs.isFile(bin.bin)).toBe(false)
		-- and against the real lune.sum, a Lune that is not the pinned macOS one is refused
		local mac =
			zn.build("darwin-wrong", { "--goos", "darwin", "--goarch", "arm64", "--lune", `{dir}/lune` })
		t.expect(mac.ok).toBe(false)
		t.expect(has(mac.stderr, "does not match lune.sum")).toBe(true)
		t.expect(fs.isFile(mac.bin)).toBe(false)
	end)

	-- Beyond AC1 (which needs only the embedded build): a build from a plain `go build` carries no payload and says so.
	it("a plain go build has no payload: version works, anything else says so and exits 3", function()
		if not zn.needGo() then
			return
		end
		local dir = zn.fresh("zn-test/bare")
		local cp = process.exec("cp", { "-R", `{zn.checkout()}/z-nile/go`, `{dir}/go` })
		t.expect(cp.ok).toBe(true)
		process.exec("rm", { "-rf", `{dir}/go/internal/payload/embedded` })
		local b = process.exec("go", { "build", "-buildvcs=false", "-o", `{dir}/zn`, "./cmd/zn" }, {
			cwd = `{dir}/go`,
			env = {
				HOME = zn.fixtureHome(),
				GOCACHE = `{zn.home()}/.cache/zn-test/go-build`,
				GOPATH = `{zn.home()}/.cache/zn-test/gopath`,
				GOTOOLCHAIN = "local",
				GOTELEMETRY = "off",
				GIT_OPTIONAL_LOCKS = "0",
			},
		})
		t.expect(b.ok).toBe(true)
		local tracker = zn.tracker("f0427-embed/bare-tracker")
		local cache = `{zn.fresh("f0427-embed/bare-cache-parent")}/never-made`
		local v = zn.run(`{dir}/zn`, tracker, cache, { "version" })
		t.expect(v.code).toBe(0)
		t.expect(has(v.stdout, "payload none")).toBe(true)
		local l = zn.run(`{dir}/zn`, tracker, cache, { "list" })
		t.expect(l.code).toBe(3)
		t.expect(has(l.stderr, "no embedded Lune")).toBe(true)
		t.expect(fs.isDir(cache)).toBe(false)
	end)
end)
