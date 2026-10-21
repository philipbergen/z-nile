--!strict
-- c0075 AC1: the Linux jail's bubblewrap command line, as a pure function of the folders a spec may write. It is the
-- whole policy: root read-only, /run hidden and read-only (host sockets) and /tmp private, the checkout's .cache and
-- the run's temp folder writable, a private /dev and /proc, and private pid, network and IPC namespaces in a session
-- of their own that die with their parent. Pure, so it runs on every platform.
local fence = require("@tests/lib/fence")
local t = require("@tests/lib/t")

local CACHE = "/work/pickman/.cache"
local TEMP = "/tmp/pickman-run.AbC123"

local function indexOf(list: { string }, value: string, from: number?): number?
	for i = from or 1, #list do
		if list[i] == value then
			return i
		end
	end
	return nil
end

local function count(list: { string }, value: string): number
	local n = 0
	for _, v in list do
		if v == value then
			n += 1
		end
	end
	return n
end

return t.spec("c0075 the Linux jail command line", function(it)
	it("is exactly the reviewed policy for the given folders", function()
		t.expect(fence.jailArgv(CACHE, TEMP, {})).toEqual({
			"bwrap",
			"--ro-bind",
			"/",
			"/",
			"--tmpfs",
			"/run",
			"--tmpfs",
			"/tmp",
			"--bind",
			CACHE,
			CACHE,
			"--bind",
			TEMP,
			TEMP,
			"--remount-ro",
			"/run",
			"--dev",
			"/dev",
			"--proc",
			"/proc",
			"--unshare-pid",
			"--unshare-net",
			"--unshare-ipc",
			"--new-session",
			"--die-with-parent",
		})
	end)

	it("mounts the root read-only first and opens the two folders after /run and /tmp are hidden", function()
		local argv = fence.jailArgv(CACHE, TEMP, {})
		local root = indexOf(argv, "--ro-bind")
		local run = indexOf(argv, "--tmpfs")
		local tmp = indexOf(argv, "--tmpfs", (run :: number) + 1)
		local cache = indexOf(argv, CACHE)
		local temp = indexOf(argv, TEMP)
		t.expect(root).toBe(2) -- right after the program name; a later mount would cover the folders
		t.expect((run :: number) > (root :: number)).toBe(true)
		t.expect((tmp :: number) > (run :: number)).toBe(true)
		t.expect((cache :: number) > (tmp :: number)).toBe(true) -- the run's temp folder lies under /tmp
		t.expect((temp :: number) > (cache :: number)).toBe(true)
	end)

	it(
		"makes /run read-only only after every bind under it, or bubblewrap cannot make their mount points",
		function()
			-- E8: with the remount first, `bwrap: Can't mkdir /run/pickman-co: Read-only file system`
			local argv = fence.jailArgv("/run/user/1000/c/.cache", "/run/user/1000/t", { "/run/media/co" })
			local remount = indexOf(argv, "--remount-ro")
			t.expect(argv[(remount :: number) + 1]).toBe("/run")
			t.expect(count(argv, "--remount-ro")).toBe(1)
			for _, path in { "/run/media/co", "/run/user/1000/c/.cache", "/run/user/1000/t" } do
				t.expect((indexOf(argv, path) :: number) < (remount :: number)).toBe(true)
			end
			t.expect((remount :: number) < (indexOf(argv, "--dev") :: number)).toBe(true)
		end
	)

	it(
		"hides /run: a tmpfs there, made read-only, so host sockets (a daemon's, the bus) are not there to connect to",
		function()
			local argv = fence.jailArgv(CACHE, TEMP, {})
			local run = indexOf(argv, "/run")
			t.expect(argv[(run :: number) - 1]).toBe("--tmpfs")
			t.expect(count(argv, "/run")).toBe(2) -- the tmpfs and its remount
		end
	)

	it("opens nothing else for writing", function()
		local argv = fence.jailArgv(CACHE, TEMP, {})
		t.expect(count(argv, "--bind")).toBe(2) -- the folders; no home, /var/tmp or /dev bind
		t.expect(count(argv, "--ro-bind")).toBe(1)
		t.expect(count(argv, "--tmpfs")).toBe(2) -- /run (made read-only after the binds) and the private /tmp
		for _, flag in { "--bind-try", "--dev-bind", "--share-net", "--chmod", "--perms" } do
			t.expect(indexOf(argv, flag)).toBe(nil)
		end
	end)

	it("unshares the pid, network and IPC namespaces, starts a session and dies with its parent", function()
		local argv = fence.jailArgv(CACHE, TEMP, {})
		for _, flag in
			{ "--unshare-pid", "--unshare-net", "--unshare-ipc", "--new-session", "--die-with-parent" }
		do
			t.expect(count(argv, flag)).toBe(1)
		end
	end)

	it(
		"keeps a checkout that lives under /tmp or /run visible, read-only, between the hiding and the folders",
		function()
			local argv = fence.jailArgv(CACHE, TEMP, { "/tmp/co", "/run/media/co/.git" })
			local ro = indexOf(argv, "--ro-bind", 3) -- the second one
			t.expect(ro ~= nil).toBe(true)
			t.expect(argv[(ro :: number) + 1]).toBe("/tmp/co")
			t.expect(argv[(ro :: number) + 2]).toBe("/tmp/co")
			t.expect(count(argv, "--ro-bind")).toBe(3)
			local tmp = indexOf(argv, "--tmpfs", (indexOf(argv, "--tmpfs") :: number) + 1)
			t.expect((ro :: number) > (tmp :: number)).toBe(true)
			t.expect((ro :: number) < (indexOf(argv, CACHE) :: number)).toBe(true)
		end
	)

	it("passes the folders through as given, spaces included, one argument each", function()
		local argv = fence.jailArgv("/a b/.cache", "/t m/p", {})
		t.expect(argv[10]).toBe("/a b/.cache")
		t.expect(argv[11]).toBe("/a b/.cache")
		t.expect(argv[13]).toBe("/t m/p")
		t.expect(argv[14]).toBe("/t m/p")
		t.expect(#argv).toBe(25)
	end)

	it("the trial is the jail with a command that does nothing, given by absolute path", function()
		-- not found through PATH: a NixOS host keeps its tools under /run, which the trial does not rebind
		local jail = fence.jailArgv(CACHE, TEMP, { "/tmp/co" })
		local trial = fence.trialArgv(CACHE, TEMP, { "/tmp/co" })
		t.expect(#trial).toBe(#jail + 3)
		t.expect({ trial[#trial - 2], trial[#trial - 1], trial[#trial] }).toEqual({ "/bin/sh", "-c", ":" })
		for i = 1, #jail do
			t.expect(trial[i]).toBe(jail[i])
		end
	end)

	it(
		"keeps what a run needs that lies under /run or /tmp: PATH entries and HOME, besides the checkout",
		function()
			-- a NixOS host reaches its tools through /run/current-system; a container may set HOME=/tmp/h
			t.expect(fence.rebindPaths({
				"/home/u/co",
				"/home/u/co/.git",
				"/run/current-system/sw/bin",
				"/usr/bin",
				"/tmp/h",
			})).toEqual({ "/run/current-system/sw/bin", "/tmp/h" })
			t.expect(fence.rebindPaths({ "/home/u/co", "/usr/bin", "/home/u" })).toEqual({})
			t.expect(fence.rebindPaths({ "/tmp/co", "/home/u/.git" })).toEqual({ "/tmp/co" }) -- the checkout itself
		end
	)

	it(
		"lists each such path once, drops one inside another, and never the folders themselves or lookalikes",
		function()
			t.expect(fence.rebindPaths({ "/tmp/h", "/tmp/h", "/tmp/h/bin", "/tmp/h2" }))
				.toEqual({ "/tmp/h", "/tmp/h2" })
			t.expect(fence.rebindPaths({ "/tmp", "/run", "/tmpfoo", "/runner/x", "" })).toEqual({})
		end
	)

	it("plans the rebinds from the checkout, git directory, every PATH entry and HOME", function()
		-- a NixOS PATH entry is a link into /nix/store: the path as given is what must exist inside
		local links: { [string]: string } = {
			["/run/current-system/sw/bin"] = "/nix/store/abc-system-path/bin",
			["/home/u/co"] = "/tmp/real-co", -- a checkout reached through a link into /tmp
		}
		local present: { [string]: boolean } = {
			["/home/u/co"] = true,
			["/home/u/co/.git"] = true,
			["/run/current-system/sw/bin"] = true,
			["/usr/bin"] = true,
			["/tmp/h"] = true,
			["/tmp/pickman-run.X"] = true,
		}
		local plan = fence.rebindPlan({
			here = "/home/u/co",
			common = "/home/u/co/.git",
			path = "/tmp/pickman-run.X/bin::/run/current-system/sw/bin:/usr/bin:relative/bin:/tmp/h/bin",
			home = "/tmp/h",
		}, function(path)
			return links[path] or path
		end, function(path)
			return present[path] == true
		end)
		-- the run's own bin folder (never made on Linux) and the relative and empty entries are skipped; /tmp/h/bin
		-- does not exist but HOME does, and covers it
		t.expect(plan).toEqual({ "/tmp/real-co", "/run/current-system/sw/bin", "/tmp/h" })
	end)

	it("plans nothing for an ordinary host, and tolerates an unset PATH or HOME", function()
		local function yes(_: string): boolean
			return true
		end
		local function same(path: string): string
			return path
		end
		t.expect(
			fence.rebindPlan(
				{ here = "/home/u/co", common = "/home/u/co/.git", path = "/usr/bin:/bin", home = "/home/u" },
				same,
				yes
			)
		).toEqual({})
		t.expect(
			fence.rebindPlan(
				{ here = "/home/u/co", common = "/home/u/co/.git", path = "", home = "" },
				same,
				yes
			)
		).toEqual({})
	end)
end)
