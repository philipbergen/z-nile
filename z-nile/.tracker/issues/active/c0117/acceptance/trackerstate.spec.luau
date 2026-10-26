--!strict
-- c0117 AC11: one definition of tracker state (design review 002 F1 to F3, F7), shared by the wrapper, the publish
-- broker, the tripwire and the watermark: git's raw diff with renames off and both sides' modes; only paths under a
-- project root's folder (with the slash) or exactly z-nile/next, only regular files, no git configuration, and no
-- change to a sequestered file but a move. The broker pushes only a fast-forward of a fresh main, never forced; two
-- brokers racing on one folder never crash, each request is answered once, and a request bound to another run is
-- refused. Pure cases, then git for real in a fixture under .cache/c0117-trackerstate.
local broker = require("@znile/engine/broker")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local paths = require("@znile/engine/paths")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerstate = require("@znile/engine/trackerstate")

local ROOTS = { "tracker", "z-nile/.tracker" }
local function e(
	status: string,
	path: string,
	oldMode: string?,
	newMode: string?,
	blob: string?
): trackerstate.Entry
	local b = blob or "a1"
	return {
		oldMode = oldMode or (if status == "A" then "000000" else "100644"),
		newMode = newMode or (if status == "D" then "000000" else "100644"),
		oldBlob = if status == "A" then "0" else b,
		newBlob = if status == "D" then "0" elseif status == "M" and not blob then b .. "e" else b,
		status = status,
		path = path,
	}
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

local base, repo, origin = "", "", ""
local function git(args: { string }): (boolean, string)
	local r = fixture.exec(repo, "git", args)
	return r.ok, (string.gsub(r.stdout, "%s+$", ""))
end
local function commit(message: string): string
	fixture.git(repo, { "add", "-A" })
	fixture.git(repo, { "commit", "-q", "-m", message })
	return fixture.git(repo, { "rev-parse", "HEAD" })
end
local function roots(_ref: string): { string }?
	return ROOTS
end

return t.spec("c0117 tracker state and the broker", function(it)
	it("reads git's raw diff, both sides and modes, renames off", function()
		local entries = trackerstate.parseRaw(
			":100644 000000 abc 000 D\tsrc/guard.lua\n:000000 100644 000 abc A\ttracker/guard.lua\n"
		) :: { trackerstate.Entry }
		t.expect(#entries).toBe(2)
		t.expect(entries[1].path).toBe("src/guard.lua")
		t.expect(entries[1].status).toBe("D")
		t.expect(entries[2].newMode).toBe("100644")
	end)

	it(
		"a rename out of a root, a root's look-alike sibling and z-nile/next's sibling are not tracker state",
		function()
			t.expect(
				has(
					trackerstate.judge({ e("D", "src/guard.lua"), e("A", "tracker/guard.lua") }, ROOTS),
					"src/guard.lua"
				)
			).toBe(true)
			t.expect(trackerstate.judge({ e("M", "tracker-x/a.md") }, ROOTS) ~= nil).toBe(true)
			t.expect(trackerstate.judge({ e("A", "z-nile/nextgen/evil.luau") }, ROOTS) ~= nil).toBe(true)
			t.expect(trackerstate.judge({ e("M", "z-nile/next") }, ROOTS)).toBe(nil)
			t.expect(trackerstate.judge({ e("M", "tracker/issues/c0010/c0010.md") }, ROOTS)).toBe(nil)
		end
	)

	it("only regular files: no symlink, no submodule, no git configuration", function()
		t.expect(has(trackerstate.judge({ e("A", "tracker/link", nil, "120000") }, ROOTS), "mode 120000"))
			.toBe(true)
		t.expect(has(trackerstate.judge({ e("A", "tracker/sub", nil, "160000") }, ROOTS), "mode 160000"))
			.toBe(true)
		t.expect(trackerstate.judge({ e("M", "tracker/x.sh", "100644", "120000") }, ROOTS) ~= nil).toBe(true)
		t.expect(trackerstate.judge({ e("A", "tracker/.gitattributes") }, ROOTS) ~= nil).toBe(true)
		t.expect(trackerstate.judge({ e("A", "tracker/.gitmodules") }, ROOTS) ~= nil).toBe(true)
		t.expect(trackerstate.judge({ e("A", "tracker/run.sh", nil, "100755") }, ROOTS)).toBe(nil)
	end)

	it("a sequestered file may be added or moved, never changed or removed", function()
		local check = "tracker/issues/c0010/check.sh"
		local spec = "tracker/issues/c0010/acceptance/a.spec.luau"
		t.expect(has(trackerstate.judge({ e("M", check) }, ROOTS, true), "sequestered")).toBe(true)
		t.expect(trackerstate.judge({ e("M", spec) }, ROOTS, true) ~= nil).toBe(true)
		t.expect(trackerstate.judge({ e("D", spec) }, ROOTS, true) ~= nil).toBe(true)
		t.expect(trackerstate.judge({ e("A", check) }, ROOTS, true)).toBe(nil)
		-- a folder move: the same blob and mode deleted at one path and added at another
		t.expect(trackerstate.judge({
			e("D", check, nil, nil, "f00d"),
			e("A", "tracker/issues/active/c0010/check.sh", nil, nil, "f00d"),
		}, ROOTS, true)).toBe(nil)
		-- a "move" that changes the content is a change
		t.expect(trackerstate.judge({
			e("D", check, nil, nil, "f00d"),
			e("A", "tracker/issues/active/c0010/check.sh", nil, nil, "beef"),
		}, ROOTS, true) ~= nil).toBe(true)
		-- without the sequestered rule (a reviewed PR's view) the same edit is tracker state
		t.expect(trackerstate.judge({ e("M", check) }, ROOTS)).toBe(nil)
	end)

	it(
		"a sequestered file is judged per item: a decoy move, another case, and a new file standing in are refused",
		function()
			-- review 003 F1 case S: the item's check.sh "moves" to another item, and a weak one is added in its new folder
			t.expect(trackerstate.judge({
				e("D", "tracker/issues/c0091/c0091.md", nil, nil, "d0c"),
				e("A", "tracker/issues/done/c0091/c0091.md", nil, nil, "d0c"),
				e("D", "tracker/issues/c0091/check.sh", nil, nil, "f00d"),
				e("A", "tracker/issues/c0099/check.sh", nil, nil, "f00d"),
				e("A", "tracker/issues/done/c0091/check.sh", nil, nil, "beef"),
			}, ROOTS, true) ~= nil).toBe(true)
			-- a spec moved to another item
			t.expect(trackerstate.judge({
				e("D", "tracker/issues/c0091/acceptance/hard.spec.luau", nil, nil, "5bec"),
				e("A", "tracker/issues/c0099/acceptance/hard.spec.luau", nil, nil, "5bec"),
			}, ROOTS, true) ~= nil).toBe(true)
			-- CHECK.SH beside check.sh (macOS would overwrite it), and any sequestered name in another case
			t.expect(
				has(
					trackerstate.judge({ e("A", "tracker/issues/c0091/CHECK.SH") }, ROOTS, true),
					"another case"
				)
			).toBe(true)
			t.expect(
				trackerstate.judge({ e("A", "tracker/issues/c0091/Acceptance/x.spec.luau") }, ROOTS, true)
					~= nil
			).toBe(true)
			t.expect(has(
				trackerstate.judge({ e("A", "tracker/issues/c0091/Notes.md") }, ROOTS, {
					result = {
						["tracker/issues/c0091/Notes.md"] = "a",
						["tracker/issues/c0091/notes.md"] = "b",
					},
				}),
				"only in case"
			)).toBe(true)
			-- an item that exists may not gain a sequestered file through the broker; a new one may
			t.expect(trackerstate.judge({ e("A", "tracker/issues/c0091/check.sh") }, ROOTS, {
				sequestered = true,
				base = { ["tracker/issues/c0091/c0091.md"] = "d0c" },
				result = {
					["tracker/issues/c0091/c0091.md"] = "d0c",
					["tracker/issues/c0091/check.sh"] = "f00d",
				},
			}) ~= nil).toBe(true)
			-- a gate's own item may change its own
			t.expect(trackerstate.judge({ e("M", "tracker/issues/c0091/check.sh") }, ROOTS, {
				sequestered = true,
				own = { c0091 = true },
			})).toBe(nil)
		end
	)

	it(
		"git's and the dispatcher's configuration in any case, and odd path components, are never tracker state",
		function()
			t.expect(trackerstate.judge({ e("A", "tracker/.GITATTRIBUTES") }, ROOTS) ~= nil).toBe(true)
			t.expect(trackerstate.judge({ e("A", "tracker/x/.GitModules") }, ROOTS) ~= nil).toBe(true)
			t.expect(
				has(
					trackerstate.judge({ e("A", "tracker/issues/c0106/.models.toml") }, ROOTS),
					"grants authority"
				)
			).toBe(true)
			t.expect(trackerstate.judge({ e("A", "tracker/.MODELS.TOML") }, ROOTS) ~= nil).toBe(true)
			t.expect(trackerstate.judge({ e("A", "tracker/../x") }, ROOTS) ~= nil).toBe(true)
			t.expect(trackerstate.judge({ e("A", "tracker/./x") }, ROOTS) ~= nil).toBe(true)
			t.expect(trackerstate.judge({ e("A", "tracker/.git/config") }, ROOTS) ~= nil).toBe(true)
			t.expect(trackerstate.judge({ e("A", "tracker/caf\\303.md") }, ROOTS) ~= nil).toBe(true)
			t.expect(trackerstate.judge({ e("A", "tracker/caf\u{e9}.md") }, ROOTS) ~= nil).toBe(true)
		end
	)

	it("sets up a fixture repository with a bare origin", function()
		local root = fixture.physical(".") :: string
		base = `{root}/.cache/c0117-trackerstate`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		repo, origin = `{base}/repo`, `{base}/origin.git`
		fs.writeDir(repo)
		process.exec("git", { "init", "-q", "-b", "main", repo })
		process.exec("git", { "init", "-q", "--bare", "-b", "main", origin })
		fixture.git(repo, { "config", "user.name", "c0117-trackerstate" })
		fixture.git(repo, { "config", "user.email", "c0117-trackerstate@example.invalid" })
		fs.writeDir(`{repo}/src`)
		fs.writeDir(`{repo}/tracker/issues/c0010`)
		fs.writeFile(`{repo}/src/guard.lua`, "return 1\n")
		fs.writeFile(`{repo}/tracker/issues/c0010/c0010.md`, "one\n")
		fs.writeFile(`{repo}/tracker/issues/c0010/check.sh`, "check\n")
		commit("seed")
		fixture.git(repo, { "remote", "add", "origin", origin })
		fixture.git(repo, { "push", "-q", "origin", "main" })
	end)

	it("through git: a rename of code into a root is refused, a tracker edit passes", function()
		local start = fixture.git(repo, { "rev-parse", "HEAD" })
		fixture.git(repo, { "mv", "src/guard.lua", "tracker/guard.lua" })
		local moved = commit("hide code")
		t.expect(has(trackerstate.check(git, start, moved, ROOTS, true), "src/guard.lua")).toBe(true)
		fixture.git(repo, { "reset", "-q", "--hard", start })
		fs.writeFile(`{repo}/tracker/issues/c0010/c0010.md`, "two\n")
		local edit = commit("tracker edit")
		t.expect(trackerstate.check(git, start, edit, ROOTS, true)).toBe(nil)
		fixture.git(repo, { "reset", "-q", "--hard", start })
	end)

	it(
		"the broker pushes a fast-forward of tracker state, and refuses code, sequestered edits and a rewind",
		function()
			fixture.check(repo)
			local start = fixture.git(repo, { "rev-parse", "HEAD" })
			fs.writeFile(`{repo}/tracker/issues/c0010/c0010.md`, "pushed\n")
			local good = commit("tracker")
			local ok, said = broker.push(repo, good, roots)
			t.expect(ok).toBe(true)
			t.expect(said).toBe("pushed")
			t.expect(fixture.git(origin, { "rev-parse", "main" })).toBe(good)
			-- code
			fs.writeFile(`{repo}/src/evil.lua`, "return 2\n")
			local code = commit("code")
			local ok2, why = broker.push(repo, code, roots)
			t.expect(ok2).toBe(false)
			t.expect(has(why, "src/evil.lua")).toBe(true)
			fixture.git(repo, { "reset", "-q", "--hard", good })
			-- a sequestered edit
			fs.writeFile(`{repo}/tracker/issues/c0010/check.sh`, "exit 0\n")
			local weakened = commit("weaken")
			t.expect((broker.push(repo, weakened, roots))).toBe(false)
			fixture.git(repo, { "reset", "-q", "--hard", good })
			-- a rewind of main to an older commit, never forced
			local ok3, why3 = broker.push(repo, start, roots)
			t.expect(ok3).toBe(false)
			t.expect(has(why3, "not a fast-forward")).toBe(true)
			t.expect(fixture.git(origin, { "rev-parse", "main" })).toBe(good)
		end
	)

	it(
		"the broker refuses the decoy move, a .models.toml, a .GITATTRIBUTES, and a history the watermark would refuse",
		function()
			fixture.git(repo, { "reset", "-q", "--hard", fixture.git(origin, { "rev-parse", "main" }) })
			local start = fixture.git(repo, { "rev-parse", "HEAD" })
			local function refused(message: string, needle: string?)
				local sha = commit(message)
				local ok, why = broker.push(repo, sha, roots)
				t.expect(ok).toBe(false)
				if needle then
					t.expect(has(why, needle)).toBe(true)
				end
				t.expect(fixture.git(origin, { "rev-parse", "main" })).toBe(start)
				fixture.git(repo, { "reset", "-q", "--hard", start })
			end
			-- case S: the decoy
			fs.writeDir(`{repo}/tracker/issues/done/c0010`)
			fs.writeDir(`{repo}/tracker/issues/c0099`)
			fixture.git(repo, { "mv", "tracker/issues/c0010/c0010.md", "tracker/issues/done/c0010/c0010.md" })
			fixture.git(repo, { "mv", "tracker/issues/c0010/check.sh", "tracker/issues/c0099/check.sh" })
			fs.writeFile(`{repo}/tracker/issues/done/c0010/check.sh`, "exit 0\n")
			refused("decoy", "sequestered")
			-- case MT: an item's own settings
			fs.writeFile(`{repo}/tracker/issues/c0010/.models.toml`, '[dispatch]\nauto_merge = ["prep"]\n')
			refused("settings", "grants authority")
			-- case GA
			fs.writeFile(`{repo}/tracker/.GITATTRIBUTES`, "* -text\n")
			refused("attributes", ".GITATTRIBUTES")
			-- case B: code, then its revert: the combined change is empty, the history is not
			fs.writeFile(`{repo}/c.lua`, "return 1\n")
			commit("code")
			fixture.git(repo, { "rm", "-q", "c.lua" })
			refused("revert", "c.lua")
		end
	)

	it(
		"a ready that rewrites its own check.sh's paths passes the broker; any other change to it does not",
		function()
			local start = fixture.git(origin, { "rev-parse", "main" })
			fixture.git(repo, { "reset", "-q", "--hard", start })
			fs.writeFile(
				`{repo}/tracker/issues/c0010/check.sh`,
				"lune run tests/run -- tracker/issues/c0010/acceptance/a.spec.luau\n"
			)
			fs.writeDir(`{repo}/tracker/issues/c0010/acceptance`)
			fs.writeFile(`{repo}/tracker/issues/c0010/acceptance/a.spec.luau`, "return nil\n")
			-- (the item's sequestered files change here only by a reviewed PR; the fixture pushes it straight)
			local seeded = commit("seed the check")
			fixture.git(repo, { "push", "-q", "origin", "HEAD:main" })
			local old = fs.readFile(`{repo}/tracker/issues/c0010/check.sh`)
			fs.writeDir(`{repo}/tracker/issues/active`)
			-- the move with one more change to the check is refused
			fixture.git(repo, { "mv", "tracker/issues/c0010", "tracker/issues/active/c0010" })
			fs.writeFile(`{repo}/tracker/issues/active/c0010/check.sh`, "exit 0\n")
			local weak = commit("weak ready")
			local okWeak, whyWeak = broker.push(repo, weak, roots)
			t.expect(okWeak).toBe(false)
			t.expect(has(whyWeak, "sequestered")).toBe(true)
			fixture.git(repo, { "reset", "-q", "--hard", seeded })
			if fs.isDir(`{repo}/tracker/issues/active/c0010`) then
				fs.removeDir(`{repo}/tracker/issues/active/c0010`)
			end
			-- ready's own rewrite of the paths passes
			fs.writeDir(`{repo}/tracker/issues/active`)
			fixture.git(repo, { "mv", "tracker/issues/c0010", "tracker/issues/active/c0010" })
			fs.writeFile(
				`{repo}/tracker/issues/active/c0010/check.sh`,
				paths.rewrite(old, { c0010 = "tracker/issues/active/c0010" })
			)
			local ready = commit("ready")
			local ok, said = broker.push(repo, ready, roots)
			t.expect(said).toBe("pushed")
			t.expect(ok).toBe(true)
		end
	)

	it("two brokers on one folder never crash, answer each request once, and refuse another run's", function()
		local dir = `{base}/broker`
		fs.writeDir(dir)
		local answered: { [string]: number } = {}
		local function push(sha: string): (boolean, string)
			answered[sha] = (answered[sha] or 0) + 1
			return true, "pushed"
		end
		for i = 1, 8 do
			fs.writeFile(
				`{dir}/r{i}.req`,
				serde.encode("json", { token = "run-1", sha = string.format("%040x", i) })
			)
		end
		fs.writeFile(
			`{dir}/stranger.req`,
			serde.encode("json", { token = "run-2", sha = string.rep("f", 40) })
		)
		local done = 0
		for _ = 1, 2 do
			task.spawn(function()
				broker.serve(dir, "run-1", push)
				done += 1
			end)
		end
		local waited = 0
		while done < 2 and waited < 5 do
			waited += task.wait(0.05)
		end
		t.expect(done).toBe(2)
		for i = 1, 8 do
			t.expect(answered[string.format("%040x", i)]).toBe(1)
			t.expect(fs.isFile(`{dir}/r{i}.res`)).toBe(true)
		end
		t.expect(answered[string.rep("f", 40)]).toBe(nil)
		local res = serde.decode("json", fs.readFile(`{dir}/stranger.res`))
		t.expect(res.ok).toBe(false)
		t.expect(has(res.message, "not this dispatcher's")).toBe(true)
	end)
end)
