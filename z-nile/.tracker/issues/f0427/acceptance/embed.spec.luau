--!strict
-- f0427 AC1 (and AC2's job on ubuntu): zn carries its Lune and engine, so it runs with no Lune on PATH; the linux build is
-- an ELF holding the Lune that lune.sum pins; a build with no pinned Lune, or none supplied, or one that does not match
-- fails with a message. Builds go through znbuild.sh into .cache/zn-test; fixtures live under .cache/f0427-embed.
-- Lune for the host build: on macOS arm64 the one rokit installed; on linux the release zip named by ZN_TEST_LUNE_ZIP
-- (the CI workflow downloads and checks it). Nothing is downloaded here.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local zn = require("./lib/zn")

local zipEnv = process.env.ZN_TEST_LUNE_ZIP

local function hostArgs(): { string }
	if zipEnv and zipEnv ~= "" then
		return { "--lune-zip", zipEnv }
	end
	return {}
end

local function mtime(path: string): number
	local at = fs.metadata(path).modifiedAt
	return if at then at.unixTimestampMillis else 0
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

return t.spec("f0427 zn embeds its Lune and engine", function(it)
	it("with PATH stripped of lune, version, list and board run", function()
		if not zn.needGo() then
			return
		end
		t.expect(process.exec("sh", { "-c", `PATH={zn.path()} command -v lune` }).ok).toBe(false)
		local built = zn.build("host", hostArgs())
		if not built.ok then
			error(`host build failed ({built.code}): {built.stderr}`, 2)
		end
		local dir = zn.tracker("f0427-embed/tracker")
		local cache = zn.fresh("f0427-embed/cache") -- fresh in this run: the extraction below is a cold one
		local v = zn.run(built.bin, dir, cache, { "version" })
		t.expect(v.code).toBe(0)
		t.expect(string.sub(v.stdout, 1, 3)).toBe("zn ")
		local id = string.match(v.stdout, "payload (%x+)")
		t.expect(string.match(v.stdout, "lune %x+ %(%a+ pin%)") ~= nil).toBe(true) -- the Lune's digest and pin kind
		t.expect(id ~= nil).toBe(true)
		local l = zn.run(built.bin, dir, cache, { "list" })
		t.expect(l.code).toBe(0)
		t.expect(has(l.stdout, "f0001")).toBe(true)
		local b = zn.run(built.bin, dir, cache, { "board", "-O" })
		t.expect(b.code).toBe(0)
		t.expect(fs.isFile(`{dir}/.cache/board.html`)).toBe(true)
		t.expect(zn.opened()).toBe("") -- nothing reached open or xdg-open
		-- extracted once: one folder named by the content id, no temporary leftovers, and a second run leaves the Lune as it was
		local names = fs.readDir(`{cache}/zn`)
		t.expect(#names).toBe(1)
		t.expect(names[1]).toBe(id)
		local lune = `{cache}/zn/{id}/bin/lune`
		local before = mtime(lune)
		t.expect(zn.run(built.bin, dir, cache, { "list" }).code).toBe(0)
		t.expect(mtime(lune)).toBe(before)
		t.expect(#fs.readDir(`{cache}/zn`)).toBe(1)
	end)

	it("the linux/amd64 build is an ELF whose payload holds the Lune a sum pins and the engine", function()
		if not zn.needGo() then
			return
		end
		local dir = zn.fresh("f0427-embed/fake")
		local marker = "FAKE-LUNE-f0427-marker"
		fs.writeFile(`{dir}/lune`, marker)
		fs.writeFile(`{dir}/lune.sum`, `bin linux-x86_64 {serde.hash("sha256", marker)} lune\n`)
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
		"with the real pinned linux Lune (the zip, when supplied) the linux build embeds exactly it",
		function()
			if not zn.needGo() then
				return
			end
			if not zipEnv or zipEnv == "" then
				print(
					"SKIPPED real linux zip: ZN_TEST_LUNE_ZIP unset; the pinned linux Lune is checked by zn-linux.yml (AC2)"
				)
				return
			end
			local built =
				zn.build("linux-real", { "--goos", "linux", "--goarch", "amd64", "--lune-zip", zipEnv })
			if not built.ok then
				error(`linux build failed ({built.code}): {built.stderr}`, 2)
			end
			local elf = fs.readFile(built.bin)
			t.expect(string.sub(elf, 1, 4)).toBe("\127ELF")
			t.expect(has(elf, fs.readFile(`{built.godir}/internal/payload/embedded/lune`))).toBe(true)
		end
	)

	it(
		"a linux build with no Lune supplied, or one that does not match lune.sum, fails with a message",
		function()
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
		end
	)

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
			env = { GOCACHE = `{zn.home()}/.cache/zn-test/go-build`, GOTOOLCHAIN = "local" },
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
