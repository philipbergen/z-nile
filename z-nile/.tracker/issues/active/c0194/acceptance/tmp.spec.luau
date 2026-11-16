--!strict
-- c0194: temporary trees live under <checkout>/.cache/.tmp (z-nile/lib/tmp.luau). The pure rules (the isolation
-- .luaurc, the Rokit leak check, which trees are stale), then the edge on stand-in checkouts under this home's .cache.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local tmp = require("@znile/lib/tmp")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local here = trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0194-tmp`
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local CLI = `{root}/z-nile/lib/tmpcli`

-- the probes a sweep asks about the machine, faked: lsof lists `busy`, pid 77777 started at "Live Start", no other pid lives
local function probes(busy: string?): tmp.Probes
	return {
		workingDirs = function()
			return if busy then { busy } else {}
		end,
		startOf = function(pid: string)
			return if pid == "77777" then "Live Start" else ""
		end,
	}
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

-- a stand-in checkout: a folder with its own .cache (never a real one)
local function checkout(name: string): string
	local dir = `{base}/{name}`
	if fs.isDir(dir) then
		must(process.exec("rm", { "-rf", dir }), "rm")
	end
	fs.writeDir(`{dir}/.cache`)
	return dir
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

return t.spec("c0194 temporary trees", function(it)
	-- ---------------------------------------------------------------------------------------- the isolation file
	it(
		"the neutralizer points every ancestor alias at a folder that does not exist, lowercased and sorted",
		function()
			local text = tmp.neutralizer({
				{
					path = "/a/.luaurc",
					text = '{"languageMode":"strict","aliases":{"Zed":"./z","apple":"./a"}}',
				},
				{ path = "/.luaurc", text = '{"aliases":{"ZED":"./other","mid":"./m"}}' },
			})
			t.expect(text).toBe(
				'{\n  "languageMode": "nonstrict",\n  "aliases": {\n'
					.. '    "apple": "./.isolated-no-such-folder",\n'
					.. '    "mid": "./.isolated-no-such-folder",\n'
					.. '    "zed": "./.isolated-no-such-folder"\n  }\n}\n'
			)
		end
	)

	it("the neutralizer with no ancestors still resets the language mode", function()
		t.expect((tmp.neutralizer({}))).toBe('{\n  "languageMode": "nonstrict",\n  "aliases": {}\n}\n')
	end)

	it("the neutralizer refuses an ancestor key it cannot reset, and one that is not strict JSON", function()
		local a, why = tmp.neutralizer({ { path = "/x/.luaurc", text = '{"lint":{"*":true}}' } })
		t.expect(a).toBe(nil)
		t.expect(has(why or "", '/x/.luaurc sets "lint"')).toBe(true)
		local b, why2 = tmp.neutralizer({ { path = "/y/.luaurc", text = "{ aliases: }" } })
		t.expect(b).toBe(nil)
		t.expect(has(why2 or "", "/y/.luaurc is not strict JSON")).toBe(true)
	end)

	-- ------------------------------------------------------------------------------------------- Rokit manifests
	it("a tool an ancestor manifest names that the tree's own manifest lacks is a leak", function()
		local leaks = tmp.rokitLeaks({
			{
				path = "/top/rokit.toml",
				text = '[tools]\nrojo = "a/rojo@1"\nlune = "b/lune@2"\nselene = "c/selene@3"\n',
			},
		}, {
			{ path = "/top/.cache/.tmp/gate/rokit.toml", text = '# pinned\n[tools]\nlune = "b/lune@9"\n' },
		})
		t.expect(leaks).toEqual({ "rojo", "selene" })
	end)

	it("a manifest line it cannot read refuses instead of guessing", function()
		local leaks, why = tmp.rokitLeaks({ { path = "/a/rokit.toml", text = "[tools]\nrojo = 7\n" } }, {})
		t.expect(leaks).toBe(nil)
		t.expect(has(why or "", "/a/rokit.toml: cannot read the tools line")).toBe(true)
	end)

	-- ------------------------------------------------------------------------------------------ which are stale
	local function entry(over: { [string]: any }): tmp.Entry
		local e = { name = "gate.abc123", link = false, newest = 0, owner = nil, ownerAlive = false }
		for k, v in over do
			(e :: any)[k] = v
		end
		return e :: tmp.Entry
	end
	local DAY = 86400
	it("a tree with no owner is stale after a day without use, not before", function()
		t.expect(tmp.stale(entry({ newest = 1000 }), 1000 + DAY, false)).toBe(true)
		t.expect(tmp.stale(entry({ newest = 1000 }), 1000 + DAY - 1, false)).toBe(false)
	end)

	it("a tree whose owner is dead is stale after an hour, one whose owner lives never", function()
		local dead = entry({ owner = "1\tx", ownerAlive = false, newest = 0 })
		t.expect(tmp.stale(dead, 3600, false)).toBe(true)
		t.expect(tmp.stale(dead, 3599, false)).toBe(false)
		t.expect(tmp.stale(entry({ owner = "1\tx", ownerAlive = true, newest = 0 }), 10 * DAY, false))
			.toBe(false)
	end)

	it("a tree a process works in, a link, a dot name or an odd name is never stale", function()
		t.expect(tmp.stale(entry({}), 10 * DAY, true)).toBe(false)
		t.expect(tmp.stale(entry({ link = true }), 10 * DAY, false)).toBe(false)
		t.expect(tmp.stale(entry({ name = ".luaurc" }), 10 * DAY, false)).toBe(false)
		t.expect(tmp.stale(entry({ name = "a b" }), 10 * DAY, false)).toBe(false)
		t.expect(tmp.stale(entry({ name = "-rf" }), 10 * DAY, false)).toBe(false)
	end)

	-- ------------------------------------------------------------------------------------------------- the edge
	local function age(path: string)
		must(process.exec("touch", { "-t", "202601010000", path }), "touch")
	end
	local function root0(co: string): string
		return tmp.root(co) :: string
	end

	it("root makes the folder with its marker, sentinel and isolation file", function()
		local co = checkout("root")
		fs.writeFile(`{co}/.luaurc`, '{"aliases":{"Extra":"./lib"}}')
		t.expect((tmp.root(co))).toBe(`{co}/.cache/.tmp`)
		t.expect(fs.isFile(`{co}/.cache/.tmp/.metadata_never_index`)).toBe(true)
		t.expect(fs.readFile(`{co}/.cache/.tmp/.git`)).toBe("gitdir: /nonexistent/pickman-fence\n")
		local luaurc = fs.readFile(`{co}/.cache/.tmp/.luaurc`)
		t.expect(has(luaurc, '"extra": "./.isolated-no-such-folder"')).toBe(true)
		t.expect(has(luaurc, '"znile": "./.isolated-no-such-folder"')).toBe(true) -- the real checkout's, above this stand-in
	end)

	it("new makes distinct fresh trees named for their kind, and an owner record only when asked", function()
		local co = checkout("new")
		local a = tmp.new(co, "gate", nil) :: string
		local b = tmp.new(co, "gate", "1") :: string
		t.expect(a ~= b).toBe(true)
		t.expect(
			string.match(a, "^" .. string.gsub(co, "%p", "%%%0") .. "/%.cache/%.tmp/gate%.[%w]+$") ~= nil
		)
			.toBe(true)
		t.expect(fs.isFile(`{a}/.pickman-owner`)).toBe(false)
		t.expect(string.match(fs.readFile(`{b}/.pickman-owner`), "^1\t") ~= nil).toBe(true)
		t.expect((tmp.new(co, "../x", nil))).toBe(nil)
	end)

	it("a .tmp or .cache that is a link or a file is refused, and nothing is written through it", function()
		local co = checkout("links")
		local stand = `{base}/links-target`
		must(process.exec("rm", { "-rf", stand }), "rm")
		fs.writeDir(stand)
		must(process.exec("ln", { "-s", stand, `{co}/.cache/.tmp` }), "ln")
		local tree, why = tmp.new(co, "gate", nil)
		t.expect(tree).toBe(nil)
		t.expect(has(why or "", "is not a plain folder")).toBe(true)
		t.expect(#fs.readDir(stand)).toBe(0)
		must(process.exec("rm", { "-f", `{co}/.cache/.tmp` }), "rm")
		fs.writeFile(`{co}/.cache/.tmp`, "")
		t.expect((tmp.root(co))).toBe(nil)
		must(process.exec("rm", { "-f", `{co}/.cache/.tmp` }), "rm")
		must(process.exec("rm", { "-rf", `{co}/.cache` }), "rm")
		must(process.exec("ln", { "-s", stand, `{co}/.cache` }), "ln")
		t.expect((tmp.root(co))).toBe(nil)
		t.expect(#fs.readDir(stand)).toBe(0)
	end)

	-- Lune finds an alias in a .luaurc above the file that requires it, so a tree below the checkout would load the
	-- checkout's aliases: the isolation file overrides them, and the tree's own .luaurc still wins
	it("a tree under .cache/.tmp resolves its own aliases and none of the checkout's above it", function()
		local co = checkout("alias")
		fs.writeDir(`{co}/lib`)
		fs.writeFile(`{co}/lib/m.luau`, "return { v = 'leaked' }\n")
		fs.writeFile(`{co}/.luaurc`, '{"aliases":{"extra":"./lib"}}')
		local tree = tmp.new(co, "probe", nil) :: string
		fs.writeDir(`{tree}/own`)
		fs.writeFile(`{tree}/own/o.luau`, "return { v = 'own' }\n")
		fs.writeFile(`{tree}/.luaurc`, '{"aliases":{"own":"./own"}}')
		fs.writeFile(
			`{tree}/main.luau`,
			'local a = pcall(require, "@extra/m")\nlocal b, o = pcall(require, "@own/o")\nprint(a, b and o.v)\n'
		)
		t.expect(trim(process.exec("lune", { "run", "main" }, { cwd = tree }).stdout)).toBe("false own")
		-- without the isolation file the checkout's alias leaks (the premise of the file)
		must(process.exec("rm", { "-f", `{co}/.cache/.tmp/.luaurc` }), "rm")
		t.expect(trim(process.exec("lune", { "run", "main" }, { cwd = tree }).stdout)).toBe("true own")
	end)

	it("verify says isolated, or why not, from the tree alone", function()
		local co = checkout("verify")
		fs.writeFile(`{co}/.luaurc`, '{"aliases":{"extra":"./lib"}}')
		local tree = tmp.new(co, "gate", nil) :: string
		-- the real checkout above this stand-in has a rokit.toml: the tree must name its tools too
		t.expect(has(tmp.verify(tree), "not isolated: rokit.toml above names")).toBe(true)
		-- a manifest in the .tmp folder itself is no tree's own
		fs.writeFile(`{co}/.cache/.tmp/rokit.toml`, fs.readFile(`{root}/rokit.toml`))
		t.expect(has(tmp.verify(tree), "not isolated: rokit.toml above names")).toBe(true)
		fs.writeFile(`{tree}/rokit.toml`, fs.readFile(`{root}/rokit.toml`))
		t.expect(tmp.verify(tree)).toBe("isolated")
		-- a tree deeper than a direct child, and one outside any .cache/.tmp, are not isolated
		fs.writeDir(`{tree}/sub`)
		t.expect(has(tmp.verify(`{tree}/sub`), "is not a direct child of a .cache/.tmp folder")).toBe(true)
		t.expect(has(tmp.verify(co), "is not a direct child of a .cache/.tmp folder")).toBe(true)
		-- an ancestor alias added since the file was written is not covered
		fs.writeFile(`{co}/.luaurc`, '{"aliases":{"extra":"./lib","later":"./l"}}')
		t.expect(has(tmp.verify(tree), ".luaurc is not what the folders above need")).toBe(true)
	end)

	it("an ancestor key the isolation cannot reset leaves the folder usable, and verify says why", function()
		local co = checkout("unreset")
		fs.writeFile(`{co}/.luaurc`, '{"lint":{"*":true}}')
		local tree = tmp.new(co, "gate", nil) :: string -- the gate's trees do not need isolation: no refusal
		t.expect(fs.isDir(tree)).toBe(true)
		t.expect(fs.isFile(`{co}/.cache/.tmp/.luaurc`)).toBe(false)
		t.expect(has(tmp.verify(tree), 'sets "lint"')).toBe(true)
	end)

	it(
		"the command line verifies the tree it was given whatever TMPDIR and ZN_TOP say (Merging's sequence)",
		function()
			local a = checkout("seq-main") -- the main checkout: the session's TMPDIR points into it
			local b = checkout("seq-worktree") -- the worktree the merge runs from: ZN_TOP
			local sessionTmp = tmp.root(a) :: string
			local env = { TMPDIR = sessionTmp, ZN_TOP = b }
			local made = must(process.exec("lune", { "run", CLI, "--", "new", "gate" }, { env = env }), "new")
			t.expect((string.find(made, `{sessionTmp}/gate.`, 1, true))).toBe(1)
			fs.writeFile(`{made}/rokit.toml`, fs.readFile(`{root}/rokit.toml`))
			local v = process.exec("lune", { "run", CLI, "--", "verify", made }, { env = env })
			t.expect(trim(v.stdout)).toBe("isolated")
			t.expect(v.ok).toBe(true)
		end
	)

	it("rm removes one tree made by new, and nothing else", function()
		local co = checkout("rm")
		local tree = tmp.new(co, "gate", nil) :: string
		fs.writeDir(`{tree}/sub`)
		local removed = tmp.removeTree(`{tree}/sub`)
		t.expect(removed).toBe(false) -- deeper than a direct child
		t.expect((tmp.removeTree(co))).toBe(false)
		t.expect((tmp.removeTree(`{co}/.cache/.tmp`))).toBe(false)
		must(process.exec("ln", { "-s", tree, `{co}/.cache/.tmp/linked.R` }), "ln")
		t.expect((tmp.removeTree(`{co}/.cache/.tmp/linked.R`))).toBe(false)
		t.expect(fs.isDir(tree)).toBe(true)
		t.expect((tmp.removeTree(tree))).toBe(true)
		t.expect(fs.isDir(tree)).toBe(false)
	end)

	-- ------------------------------------------------------------------------------------------- the stale sweep
	it(
		"a sweep removes the old unowned tree and keeps the young one, the busy one, the link and the dot files",
		function()
			local co = checkout("sweep")
			local r0 = root0(co)
			for _, n in { "old.A", "young.B", "busy.C" } do
				fs.writeDir(`{r0}/{n}`)
				fs.writeFile(`{r0}/{n}/f`, "x")
			end
			for _, n in { "old.A/f", "old.A", "busy.C/f", "busy.C" } do
				age(`{r0}/{n}`)
			end
			must(process.exec("ln", { "-s", `{base}`, `{r0}/linky` }), "ln")
			local dry = tmp.sweep(co, true, probes(`{r0}/busy.C`)) :: { string }
			t.expect(#dry).toBe(1)
			t.expect(has(dry[1], `{r0}/old.A`)).toBe(true)
			t.expect(fs.isDir(`{r0}/old.A`)).toBe(true)
			local real = tmp.sweep(co, false, probes(`{r0}/busy.C`)) :: { string }
			t.expect(#real).toBe(1)
			t.expect(fs.isDir(`{r0}/old.A`)).toBe(false)
			for _, keep in { "young.B", "busy.C", "linky", ".luaurc", ".git", ".metadata_never_index" } do
				t.expect(
					fs.isDir(`{r0}/{keep}`)
						or fs.isFile(`{r0}/{keep}`)
						or process.exec("test", { "-L", `{r0}/{keep}` }).ok
				).toBe(true)
			end
			t.expect(fs.isDir(base)).toBe(true) -- the link's target is untouched
		end
	)

	it("a sweep that cannot tell what is in use removes nothing", function()
		local co = checkout("nolsof")
		local r0 = root0(co)
		fs.writeDir(`{r0}/old.A`)
		age(`{r0}/old.A`)
		local none: tmp.Probes = {
			workingDirs = function()
				return nil
			end,
			startOf = function()
				return ""
			end,
		}
		local found, why = tmp.sweep(co, false, none)
		t.expect(found).toBe(nil)
		t.expect(has(why or "", "nothing swept")).toBe(true)
		t.expect(fs.isDir(`{r0}/old.A`)).toBe(true)
	end)

	it(
		"a tree whose recorded owner is alive survives a sweep, a dead or replaced owner's does not",
		function()
			local co = checkout("owner")
			local r0 = root0(co)
			local function owned(name: string, record: string): string
				local tree = tmp.new(co, name, nil) :: string
				fs.writeFile(`{tree}/.pickman-owner`, record)
				age(`{tree}/.pickman-owner`)
				age(tree)
				return tree
			end
			local live = owned("live", "77777\tLive Start\n")
			local reused = owned("reused", "77777\tAnother Start\n") -- the pid lives, but it is not the owner
			local dead = owned("dead", "99998\tAny Start\n")
			local unknown = owned("unknown", "99998\t?\n") -- recorded where ps could not answer; the pid is gone
			tmp.sweep(co, false, probes(nil))
			t.expect(fs.isDir(live)).toBe(true)
			t.expect(fs.isDir(reused)).toBe(false)
			t.expect(fs.isDir(dead)).toBe(false)
			t.expect(fs.isDir(unknown)).toBe(false)
			t.expect(fs.isDir(r0)).toBe(true)
		end
	)

	it("a change deep inside a tree counts against the window of the rule that judges it", function()
		local co = checkout("deep")
		local r0 = root0(co)
		local function withDeepFile(name: string, record: string?): string
			local tree = tmp.new(co, name, nil) :: string
			fs.writeDir(`{tree}/a/b`)
			fs.writeFile(`{tree}/a/b/f`, "x")
			if record then
				fs.writeFile(`{tree}/.pickman-owner`, record)
			end
			-- the deep file was changed 2 hours ago, everything the shallow look sees is old
			local twoHours = os.date("%Y%m%d%H%M", os.time() - 7200)
			must(process.exec("touch", { "-t", twoHours, `{tree}/a/b/f` }), "touch")
			for _, p in { `{tree}/a/b`, `{tree}/a`, `{tree}/.pickman-owner`, tree } do
				if process.exec("test", { "-e", p }).ok then
					age(p)
				end
			end
			return tree
		end
		local dead = withDeepFile("deaddeep", "99998\tAny Start\n")
		local unowned = withDeepFile("unowneddeep", nil)
		tmp.sweep(co, false, probes(nil))
		t.expect(fs.isDir(dead)).toBe(false) -- a dead owner's tree: idle for an hour is enough
		t.expect(fs.isDir(unowned)).toBe(true) -- an unowned tree: a change within the day keeps it
		t.expect(fs.isDir(r0)).toBe(true)
	end)

	it("an owner whose liveness ps cannot answer is taken as alive", function()
		local co = checkout("psdown")
		local r0 = root0(co)
		local tree = tmp.new(co, "held", nil) :: string
		fs.writeFile(`{tree}/.pickman-owner`, "99998\tAny Start\n")
		age(`{tree}/.pickman-owner`)
		age(tree)
		local down: tmp.Probes = {
			workingDirs = function()
				return {}
			end,
			startOf = function()
				return nil
			end,
		}
		tmp.sweep(co, false, down)
		t.expect(fs.isDir(tree) and fs.isDir(r0)).toBe(true)
	end)

	it(
		"the sweep's command line says each tree it removes, or would remove, on stderr and nothing on stdout",
		function()
			local co = checkout("report")
			local r0 = root0(co)
			fs.writeDir(`{r0}/old.A`)
			age(`{r0}/old.A`)
			local stubs = `{co}-stubs`
			must(process.exec("rm", { "-rf", stubs }), "rm")
			fs.writeDir(stubs)
			fs.writeFile(`{stubs}/lsof`, "#!/bin/sh\ntrue\n")
			must(process.exec("chmod", { "+x", `{stubs}/lsof` }), "chmod")
			local env = { PATH = `{stubs}:{process.env.PATH or ""}`, HOME = process.env.HOME or "" }
			local dry = process.exec(
				"lune",
				{ "run", CLI, "--", "sweep", "--dry-run", "--dir", co },
				{ env = env }
			)
			t.expect(dry.ok and dry.stdout == "").toBe(true)
			t.expect(has(dry.stderr, `tmp: would remove {r0}/old.A (idle `)).toBe(true)
			t.expect(fs.isDir(`{r0}/old.A`)).toBe(true)
			local real = process.exec("lune", { "run", CLI, "--", "sweep", "--dir", co }, { env = env })
			t.expect(real.ok and real.stdout == "").toBe(true)
			t.expect(has(real.stderr, `tmp: removed {r0}/old.A (idle `)).toBe(true)
			t.expect(fs.isDir(`{r0}/old.A`)).toBe(false)
		end
	)

	it(
		"removal enters the folder by its physical path, so a link swapped in deletes nothing elsewhere",
		function()
			local co = checkout("swap")
			local r0 = root0(co)
			fs.writeDir(`{r0}/victim.A`)
			local stand = `{base}/swap-target`
			must(process.exec("rm", { "-rf", stand }), "rm")
			fs.writeDir(`{stand}/victim.A`)
			fs.writeFile(`{stand}/victim.A/keep`, "x")
			local moved = `{co}/.cache/.tmp-real`
			must(process.exec("mv", { r0, moved }), "mv")
			must(process.exec("ln", { "-s", stand, r0 }), "ln")
			t.expect(tmp.remove(r0, "victim.A")).toBe(false)
			t.expect(fs.isFile(`{stand}/victim.A/keep`)).toBe(true)
			t.expect(tmp.remove(moved, "victim.A")).toBe(true)
			t.expect(fs.isDir(`{moved}/victim.A`)).toBe(false)
			t.expect(tmp.remove(moved, "../escape")).toBe(false)
			t.expect(tmp.remove(moved, ".luaurc")).toBe(false)
		end
	)

	it(
		"the jail profile is the spec jail's rule set for the clone: /dev, TMPDIR and the .cache folders it is given, not the sources",
		function()
			local pTree = "/private/a/.cache/.tmp/unguarded.X"
			local caches = { `{pTree}/repo/.cache`, `{pTree}/repo/z-nile/.cache` }
			local profile = tmp.jailProfile(pTree, caches)
			t.expect(has(profile, '(deny file-write* (subpath "/"))')).toBe(true)
			t.expect(has(profile, '(allow file-write* (subpath "/dev"))')).toBe(true)
			t.expect(has(profile, `(allow file-write* (subpath "{pTree}/.jail-tmp"))`)).toBe(true)
			-- each folder it is given is opened by name
			for _, c in caches do
				t.expect(has(profile, `(allow file-write* (subpath "{c}"))`)).toBe(true)
				-- the entry itself, and a symlink at its top, are refused (the runner's rule)
				t.expect(has(profile, `(deny file-write* (literal "{c}"))`)).toBe(true)
			end
			t.expect(
				has(
					profile,
					'(deny file-write-create (require-all (vnode-type SYMLINK) (regex #"^/private/a/\\.cache/\\.tmp/unguarded\\.X/repo/\\.cache/[^/]+$")))'
				)
			).toBe(true)
			-- never the tree itself, and no allow rule is a pattern over names the command can create (review 004 F1: a
			-- `.cache` folder made inside the sources or the git directory must stay read-only)
			t.expect(has(profile, `(allow file-write* (subpath "{pTree}"))`)).toBe(false)
			t.expect(has(profile, "(allow file-write* (regex")).toBe(false)
			t.expect(has(profile, "(deny network-outbound (remote ip))")).toBe(true)
			t.expect(has(profile, '(allow network-outbound (remote ip "localhost:*"))')).toBe(true)
			t.expect(has(profile, "(deny signal (with no-log))")).toBe(true)
			t.expect(has(profile, "(allow signal (target same-sandbox))")).toBe(true)
			local allows = 0
			for _ in string.gmatch(profile, "%(allow file%-write%*") do
				allows += 1
			end
			t.expect(allows).toBe(4) -- /dev, TMPDIR, and the two caches
			-- later rules win: every deny of an entry comes after the allows
			local lastAllow = 0
			for at in string.gmatch(profile, "()%(allow file%-write%*") do
				lastAllow = at
			end
			local firstEntryDeny = string.find(profile, "(deny file-write* (literal", 1, true) :: number
			t.expect(firstEntryDeny > lastAllow).toBe(true)
			-- none given (a tree with no checkout in it yet): only /dev and TMPDIR
			local bareProfile = tmp.jailProfile(pTree, {})
			t.expect(has(bareProfile, "(literal")).toBe(false)
			t.expect(has(bareProfile, `(subpath "{pTree}/.jail-tmp")`)).toBe(true)
			local co = checkout("jail")
			local tree = tmp.new(co, "unguarded", nil) :: string
			local inherited = { ceilings = "/x/.cache", realGit = "/real/.git", common = "/here/.git" }
			local plan = tmp.jailPlan(tree, { "sh", "-c", "true" }, inherited) :: tmp.JailPlan
			t.expect(plan.cwd).toBe(tree) -- the command runs in the tree, not where ./zn ran
			local argv = plan.argv
			t.expect(argv[1]).toBe("sandbox-exec")
			t.expect(argv[4]).toBe("env")
			t.expect(argv[5]).toBe(`TMPDIR={tree}/.jail-tmp`)
			-- the spec runner takes the clone for a fixture of this checkout: the tree's .cache joins the ceiling, and this
			-- checkout's git directory joins the real ones
			t.expect(argv[6]).toBe(`GIT_CEILING_DIRECTORIES=/x/.cache:{co}/.cache`)
			t.expect(argv[7]).toBe("PICKMAN_FENCE_REAL_GIT=/real/.git:/here/.git")
			t.expect(argv[8]).toBe("sh")
			-- the profile opens the .cache folders the plan made first, and only those (review 004 F1)
			fs.writeDir(`{tree}/repo`)
			fs.writeFile(`{tree}/repo/.git`, "gitdir: x")
			fs.writeDir(`{tree}/repo/deep/er`)
			local withRepo = tmp.jailPlan(tree, { "true" }, inherited) :: tmp.JailPlan
			t.expect(fs.isDir(`{tree}/repo/.cache`)).toBe(true)
			t.expect(has(withRepo.argv[3], `(allow file-write* (subpath "{tree}/repo/.cache"))`)).toBe(true)
			t.expect(has(withRepo.argv[3], `{tree}/repo/deep`)).toBe(false)
			-- a folder that is not a tree made by `new` is refused before anything is written in it
			fs.writeDir(`{co}/sub`)
			fs.writeFile(`{co}/sub/.git`, "gitdir: x")
			t.expect((tmp.jailPlan(co, { "true" }, inherited))).toBe(nil)
			t.expect(fs.isDir(`{co}/sub/.cache`)).toBe(false)
			local bare = tmp.jailPlan(
				tree,
				{ "true" },
				{ ceilings = "", realGit = "", common = "/here/.git" }
			) :: tmp.JailPlan
			t.expect(bare.argv[6]).toBe(`GIT_CEILING_DIRECTORIES={co}/.cache`)
			t.expect(bare.argv[7]).toBe("PICKMAN_FENCE_REAL_GIT=/here/.git")
			t.expect((tmp.jailPlan(co, { "true" }, inherited))).toBe(nil) -- not a tree under a .cache/.tmp
			t.expect((tmp.jailPlan(`{co}/.cache/.tmp`, { "true" }, inherited))).toBe(nil) -- the folder itself
			t.expect((tmp.jailPlan(tree, {}, inherited))).toBe(nil) -- no command
			must(process.exec("ln", { "-s", tree, `{co}/.cache/.tmp/linked.Z` }), "ln")
			t.expect((tmp.jailPlan(`{co}/.cache/.tmp/linked.Z`, { "true" }, inherited))).toBe(nil)
		end
	)

	-- ------------------------------------------------------------------------------ where a new tree goes
	it(
		"without a folder named, a TMPDIR inside a .cache/.tmp is where the tree goes; otherwise the checkout's",
		function()
			local co = checkout("place")
			local own = tmp.root(co) :: string
			local run = `{own}/pickman-run.X`
			fs.writeDir(run)
			local viaRun = trim(
				process.exec("lune", { "run", CLI, "--", "new", "par" }, { env = { TMPDIR = run }, cwd = co }).stdout
			)
			t.expect((string.find(viaRun, `{run}/par.`, 1, true))).toBe(1)
			local viaTop = trim(
				process.exec("lune", { "run", CLI, "--", "new", "par" }, { env = { TMPDIR = own }, cwd = co }).stdout
			)
			t.expect((string.find(viaTop, `{own}/par.`, 1, true))).toBe(1)
			local viaCwd = trim(
				process.exec(
					"lune",
					{ "run", CLI, "--", "new", "par" },
					{ env = { TMPDIR = "/c0194-no-such-tmpdir", ZN_TOP = co }, cwd = co }
				).stdout
			)
			t.expect((string.find(viaCwd, `{own}/par.`, 1, true))).toBe(1)
			t.expect(viaCwd ~= viaTop).toBe(true)
			-- a TMPDIR folder that is a link is refused
			must(process.exec("rm", { "-rf", `{base}/place-target` }), "rm")
			fs.writeDir(`{base}/place-target`)
			must(process.exec("ln", { "-s", `{base}/place-target`, `{own}/linked` }), "ln")
			local bad = process.exec(
				"lune",
				{ "run", CLI, "--", "new", "par" },
				{ env = { TMPDIR = `{own}/linked` }, cwd = co }
			)
			t.expect(bad.ok).toBe(false)
			t.expect(#fs.readDir(`{base}/place-target`)).toBe(0)
		end
	)

	-- ------------------------------------------------------------------------------------- the command line
	it(
		"the command line makes, verifies and sweeps; leftovers lists, and removes only what is named",
		function()
			local co = checkout("cli")
			local made = must(process.exec("lune", { "run", CLI, "--", "new", "gate", "--dir", co }), "new")
			t.expect((string.find(made, `{co}/.cache/.tmp/gate.`, 1, true))).toBe(1)
			t.expect(trim(process.exec("lune", { "run", CLI, "--", "root", "--dir", co }).stdout))
				.toBe(`{co}/.cache/.tmp`)
			local v = process.exec("lune", { "run", CLI, "--", "verify", made, "--dir", co })
			t.expect(has(v.stdout, "not isolated")).toBe(true)
			t.expect(v.ok).toBe(false)
			local s = process.exec("lune", { "run", CLI, "--", "sweep", "--dry-run", "--dir", co })
			t.expect(s.ok or has(s.stderr, "nothing swept")).toBe(true) -- lsof may be refused inside the jail
			t.expect(process.exec("lune", { "run", CLI, "--", "bogus" }).ok).toBe(false)
		end
	)

	it("prepareCaches makes the .cache of each checkout and home in the tree, and refuses a link", function()
		local co = checkout("prep")
		local tree = tmp.new(co, "unguarded", nil) :: string
		fs.writeDir(`{tree}/repo/z-nile/.tracker`)
		fs.writeDir(`{tree}/repo/scripts`)
		fs.writeFile(`{tree}/repo/.git`, "gitdir: x")
		fs.writeFile(`{tree}/repo/zn`, "#!/bin/sh")
		fs.writeFile(`{tree}/notes`, "x")
		fs.writeDir(`{tree}/docs`) -- a folder at the top that is no checkout (no .git)
		local made = tmp.prepareCaches(tree) :: { string }
		t.expect(table.concat(made, "\n")).toBe(`{tree}/repo/.cache\n{tree}/repo/z-nile/.cache`)
		t.expect(fs.isDir(`{tree}/repo/scripts/.cache`)).toBe(false) -- not a home
		t.expect(fs.isDir(`{tree}/docs/.cache`)).toBe(false) -- not a checkout
		must(process.exec("rm", { "-rf", `{tree}/repo/.cache` }), "rm")
		must(process.exec("ln", { "-s", base, `{tree}/repo/.cache` }), "ln")
		local none, why = tmp.prepareCaches(tree)
		t.expect(none).toBe(nil)
		t.expect(has(why or "", "is not a plain folder")).toBe(true)
	end)

	-- ./zn tmp jail itself, run for real with a stand-in sandbox-exec first on PATH (a sandbox cannot nest in this jail): it
	-- takes -p <profile> and runs the rest, so everything the command line does around it is exercised
	it(
		"the jail command runs in the tree, with TMPDIR, the ceiling and the real git directory, and passes the exit code on",
		function()
			local co = checkout("jailcli")
			local tree = tmp.new(co, "unguarded", nil) :: string
			fs.writeDir(`{tree}/repo`)
			fs.writeFile(`{tree}/repo/.git`, "gitdir: x")
			local stubs = `{co}-stubs`
			must(process.exec("rm", { "-rf", stubs }), "rm")
			fs.writeDir(stubs)
			fs.writeFile(
				`{stubs}/sandbox-exec`,
				`#!/bin/sh\n[ "$1" = -p ] || exit 97\nprintf '%s' "$2" > '{co}-profile'\nshift 2\nexec "$@"\n`
			)
			must(process.exec("chmod", { "+x", `{stubs}/sandbox-exec` }), "chmod")
			local env = {
				PATH = `{stubs}:{process.env.PATH or ""}`,
				GIT_CEILING_DIRECTORIES = "/x/.cache",
				PICKMAN_FENCE_REAL_GIT = "/real/.git",
			}
			local r = process.exec("lune", {
				"run",
				CLI,
				"--",
				"jail",
				tree,
				"--",
				"sh",
				"-c",
				'pwd; echo "$TMPDIR"; test -d "$TMPDIR" && echo tmpdir-exists; echo "$GIT_CEILING_DIRECTORIES|$PICKMAN_FENCE_REAL_GIT"; test -d repo/.cache && echo cache-made; exit 3',
			}, { env = env })
			t.expect(r.code).toBe(3)
			local lines = string.split(trim(r.stdout), "\n")
			t.expect(lines[1]).toBe(tree)
			t.expect(lines[2]).toBe(`{tree}/.jail-tmp`)
			t.expect(lines[3]).toBe("tmpdir-exists")
			t.expect(
				string.find(
					lines[4] or "",
					"^/x/%.cache:" .. string.gsub(co, "%p", "%%%0") .. "/%.cache|/real/%.git:"
				) ~= nil
			).toBe(true)
			t.expect(lines[5]).toBe("cache-made")
			t.expect(has(fs.readFile(`{co}-profile`), '(deny file-write* (subpath "/"))')).toBe(true)
			-- refusals reach the command line: the folder itself, a deeper path, nothing, an empty name
			for _, bad in { `{co}/.cache/.tmp`, `{tree}/repo`, "" } do
				local refused = process.exec(
					"lune",
					{ "run", CLI, "--", "jail", bad, "--", "true" },
					{ env = env }
				)
				t.expect(refused.ok).toBe(false)
				t.expect((string.find(refused.stderr, "tmp: ", 1, true))).toBe(1)
				t.expect(has(refused.stderr, "stack traceback")).toBe(false)
			end
		end
	)

	it(
		"an owner record is one format whoever writes it, and the sweep reads it with the same perl",
		function()
			t.expect(tmp.STARTED).toBe(fence.STARTED)
			local pid = trim(process.exec("sh", { "-c", "echo $PPID" }).stdout)
			t.expect(tmp.startOf(pid)).toBe(fence.startOf(pid) or "")
			t.expect(tmp.startOf("99998")).toBe("")
			local co = checkout("ownerfmt")
			local tree = tmp.new(co, "held", pid) :: string
			local rec = fs.readFile(`{tree}/.pickman-owner`)
			t.expect(rec).toBe(`{pid}\t{fence.startOf(pid) or ""}\n`)
		end
	)

	it(
		"a start record the sweep cannot read keeps the tree, as the runner's reader does; a dead pid does not",
		function()
			local co = checkout("unreadable")
			local r0 = tmp.root(co) :: string
			local function stubDir(name: string, perlExit: number?): string
				local dir = `{co}-{name}`
				must(process.exec("rm", { "-rf", dir }), "rm")
				fs.writeDir(dir)
				fs.writeFile(`{dir}/lsof`, "#!/bin/sh\ntrue\n")
				must(process.exec("chmod", { "+x", `{dir}/lsof` }), "chmod")
				if perlExit then
					-- a perl that fails the start-record snippet with this exit code, the real one for everything else
					local realPerl = trim(process.exec("sh", { "-c", "command -v perl" }).stdout)
					fs.writeFile(
						`{dir}/perl`,
						`#!/bin/sh\n[ "$1" = -e ] && exit {perlExit}\nexec {realPerl} "$@"\n`
					)
					must(process.exec("chmod", { "+x", `{dir}/perl` }), "chmod")
				end
				return dir
			end
			fs.writeDir(`{r0}/held.A`)
			fs.writeFile(`{r0}/held.A/.pickman-owner`, "99998\tX\n")
			age(`{r0}/held.A/.pickman-owner`)
			age(`{r0}/held.A`)
			local function sweepWith(dir: string)
				return process.exec("lune", { "run", CLI, "--", "sweep", "--dir", co }, {
					env = { PATH = `{dir}:{process.env.PATH or ""}` },
				})
			end
			-- exit 2 is the snippet's "cannot tell"; any other failure (a perl that dies) is no answer either: both keep the tree
			for _, code in { 2, 255 } do
				t.expect(sweepWith(stubDir(`blind{code}`, code)).ok).toBe(true)
				t.expect(fs.isDir(`{r0}/held.A`)).toBe(true) -- cannot tell: the owner is taken as alive, nothing swept
			end
			t.expect(tmp.startOf("99998")).toBe("") -- the real reader: no such process
			t.expect(sweepWith(stubDir("sighted", nil)).ok).toBe(true)
			t.expect(fs.isDir(`{r0}/held.A`)).toBe(false) -- the owner's pid is gone: swept
		end
	)

	it("the sweep also covers the project homes' folders and the session's TMPDIR folder", function()
		local main = checkout("sweephome")
		fs.writeDir(`{main}/z-nile/.tracker`)
		local homeRoot = tmp.root(`{main}/z-nile`) :: string
		local sessionCo = checkout("sweepsession")
		local sessionRoot = tmp.root(sessionCo) :: string
		for _, r0 in { homeRoot, sessionRoot } do
			fs.writeDir(`{r0}/old.A`)
			age(`{r0}/old.A`)
		end
		local stubs = `{main}-stubs`
		must(process.exec("rm", { "-rf", stubs }), "rm")
		fs.writeDir(stubs)
		fs.writeFile(`{stubs}/lsof`, "#!/bin/sh\ntrue\n")
		must(process.exec("chmod", { "+x", `{stubs}/lsof` }), "chmod")
		local env = { PATH = `{stubs}:{process.env.PATH or ""}`, TMPDIR = sessionRoot }
		local r = process.exec("lune", { "run", CLI, "--", "sweep", "--dir", main }, { env = env })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isDir(`{homeRoot}/old.A`)).toBe(false) -- a home's folder
		t.expect(fs.isDir(`{sessionRoot}/old.A`)).toBe(false) -- the session's, named by TMPDIR alone
	end)

	it("a TMPDIR that is exactly a .cache/.tmp makes new refresh its isolation file", function()
		local co = checkout("fresh")
		local own = tmp.root(co) :: string
		fs.writeFile(`{co}/.luaurc`, '{"aliases":{"later":"./l"}}')
		t.expect(has(fs.readFile(`{own}/.luaurc`), "later")).toBe(false)
		local env = { TMPDIR = own }
		must(process.exec("lune", { "run", CLI, "--", "new", "gate" }, { env = env }), "new")
		t.expect(has(fs.readFile(`{own}/.luaurc`), '"later"')).toBe(true)
	end)

	it("rm and verify refuse an empty or missing tree with a message, not a stack trace", function()
		for _, args in
			{
				{ "rm", "" },
				{ "rm", `{base}/no-such-tree` },
				{ "verify", "" },
				{ "verify", `{base}/no-such-tree` },
			}
		do
			local all = { "run", CLI, "--" }
			for _, a in args do
				table.insert(all, a)
			end
			local r = process.exec("lune", all)
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr .. r.stdout, "stack traceback")).toBe(false)
			t.expect(has(r.stderr .. r.stdout, "tmp: ") or has(r.stdout, "not isolated")).toBe(true)
		end
	end)

	it("leftovers lists the tooling's old trees and removes only the names it is given", function()
		local dir = `{base}/leftovers`
		must(process.exec("rm", { "-rf", dir }), "rm")
		for _, n in { "tmp.AAA/repo/.git", "tmp.BBB", "pickman-run.CCC", "unrelated" } do
			fs.writeDir(`{dir}/{n}`)
		end
		local lines = tmp.leftovers({}, dir)
		t.expect(#lines).toBe(3)
		for _, line in lines do
			t.expect(has(line, "REMOVED")).toBe(false)
		end
		t.expect(has(lines[1] .. lines[2] .. lines[3], "repo")).toBe(true)
		local after = tmp.leftovers({ "tmp.BBB", "unrelated" }, dir)
		t.expect(#after).toBe(3)
		t.expect(fs.isDir(`{dir}/tmp.BBB`)).toBe(false)
		t.expect(
			fs.isDir(`{dir}/tmp.AAA`) and fs.isDir(`{dir}/pickman-run.CCC`) and fs.isDir(`{dir}/unrelated`)
		)
			.toBe(true)
	end)
end)
