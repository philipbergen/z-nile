--!strict
-- c0075 AC2: what the runner does when a spec run cannot be put in a jail (Linux without a working bubblewrap, as on
-- macOS inside another sandbox), and how it explains a Linux failure. Pure functions of what the probes found.
local fence = require("@tests/lib/fence")
local t = require("@tests/lib/t")

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

return t.spec("c0075 a run that cannot be jailed", function(it)
	it("goes on when the outer sandbox leaves nothing open", function()
		local v = fence.fallback("some reason", {}, {}, false)
		t.expect(v.kind).toBe("protected")
		t.expect(has(v.message, "not jailed (some reason)")).toBe(true)
		t.expect(has(v.message, "protects the repository")).toBe(true)
	end)

	it(
		"goes on as a fixture of a guarded checkout only when nothing but the run's own paths is open",
		function()
			t.expect(fence.fallback("r", { "/work/fx" }, {}, true).kind).toBe("fixture")
			t.expect(fence.fallback("r", { "/work/fx" }, { "the network" }, true).kind).toBe("refuse")
			t.expect(fence.fallback("r", { "/work/fx" }, {}, false).kind).toBe("refuse")
		end
	)

	it("refuses when the repository can be written, naming the reason and everything open", function()
		local v = fence.fallback(
			"bwrap is missing",
			{ "/work/pickman", "/work/pickman/.git" },
			{ "the network" },
			false
		)
		t.expect(v.kind).toBe("refuse")
		t.expect(has(v.message, "cannot jail this run (bwrap is missing)")).toBe(true)
		t.expect(has(v.message, "/work/pickman, /work/pickman/.git, the network")).toBe(true)
		t.expect(has(v.message, "Specs never touch the real repository")).toBe(true)
	end)

	it("refuses when only a leak is open, even with nothing writable", function()
		t.expect(fence.fallback("r", {}, { "the home folder /home/x" }, false).kind).toBe("refuse")
	end)

	it("says bubblewrap is missing when there is no program", function()
		local why = fence.linuxWhy(nil, "")
		t.expect(has(why, "not installed")).toBe(true)
		t.expect(has(why, "scripts/linux-jail.sh")).toBe(true)
	end)

	it("names the Ubuntu user-namespace restriction for the errors bubblewrap gives there", function()
		for _, stderr in
			{
				"bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted\n",
				"bwrap: No permissions to create new namespace, likely because the kernel does not allow non-privileged user namespaces.",
				"bwrap: setting up uid map: Permission denied",
				"bwrap: Creating new namespace failed: Operation not permitted",
			}
		do
			local why = fence.linuxWhy("/usr/bin/bwrap", stderr)
			t.expect(has(why, "user namespace")).toBe(true)
			t.expect(has(why, "kernel.apparmor_restrict_unprivileged_userns")).toBe(true)
			t.expect(has(why, "scripts/linux-jail.sh --apply-sysctl")).toBe(true)
		end
	end)

	it("does not blame the restriction for an error that is something else", function()
		for _, stderr in
			{
				"bwrap: Can't mount proc on /newroot/proc: Operation not permitted",
				"bwrap: Can't find source path /work/x: Permission denied",
			}
		do
			local why = fence.linuxWhy("/usr/bin/bwrap", stderr)
			t.expect(has(why, "user namespace")).toBe(false)
			t.expect(has(why, "bwrap: Can't")).toBe(true)
			t.expect(has(why, "--apply-sysctl")).toBe(false)
		end
	end)

	it("says a jail could not nest when the run is already inside one", function()
		local why = fence.linuxWhy(
			"/usr/bin/bwrap",
			"bwrap: Creating new namespace failed: Operation not permitted",
			"bwrap"
		)
		t.expect(has(why, "inside the run's own jail")).toBe(true)
		t.expect(has(why, "--apply-sysctl")).toBe(false)
		t.expect(
			has(fence.linuxWhy("/usr/bin/bwrap", "bwrap: x", "sandbox-exec"), "inside the run's own jail")
		)
			.toBe(false)
		t.expect(has(fence.linuxWhy("/usr/bin/bwrap", "bwrap: x", nil), "inside the run's own jail"))
			.toBe(false)
	end)

	it("quotes the first line of any other bubblewrap failure", function()
		local why = fence.linuxWhy(
			"/usr/bin/bwrap",
			"bwrap: Can't find source path /nonexistent: No such file or directory\nsecond\n"
		)
		t.expect(has(why, "Can't find source path /nonexistent")).toBe(true)
		t.expect(has(why, "second")).toBe(false)
		t.expect(has(why, "user namespace")).toBe(false)
	end)

	it("an outer sandbox must close each shared folder of its platform", function()
		t.expect(fence.escapePaths("linux")).toEqual({ "/tmp", "/var/tmp", "/dev/shm", "$XDG_RUNTIME_DIR" })
		t.expect(fence.escapePaths("macos")).toEqual({ "/private/tmp", "getconf:DARWIN_USER_TEMP_DIR" })
		t.expect(fence.escapePaths("windows")).toEqual({})
	end)

	it("reads a closed network from the error of the platform", function()
		t.expect(fence.networkClosed("macos", "Operation not permitted")).toBe(true)
		t.expect(fence.networkClosed("linux", "Operation not permitted")).toBe(true)
		t.expect(fence.networkClosed("linux", "Network is unreachable")).toBe(true)
		t.expect(fence.networkClosed("macos", "Network is unreachable")).toBe(false) -- a macOS host with no route is no sandbox
		t.expect(fence.networkClosed("linux", "Connection timed out")).toBe(false)
		t.expect(fence.networkClosed("linux", "connected")).toBe(false)
	end)

	it("reads a refused liveness probe as alive only where signals outside are refused", function()
		local refused = { ok = false, stderr = "kill: (1) - Operation not permitted" }
		t.expect(fence.reads(refused, "sandbox-exec")).toBe(true)
		t.expect(fence.reads(refused, "outer sandbox (protects the repository)")).toBe(true)
		t.expect(fence.reads(refused, "bwrap")).toBe(false) -- a pid outside the namespace is absent, never refused
		t.expect(fence.reads(refused, "none (unjailed)")).toBe(false)
		t.expect(fence.reads({ ok = false, stderr = "kill: (7) - No such process" }, "sandbox-exec"))
			.toBe(false)
		t.expect(fence.reads({ ok = true, stderr = "" }, "none (unjailed)")).toBe(true)
	end)

	it(
		"reports each shared folder that is writable, resolving variables and getconf names through the lookup",
		function()
			local fs = require("@lune/fs")
			local process = require("@lune/process")
			local root = (
				string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
			)
			local base = `{root}/.cache/c0075-leaks`
			if fs.isDir(base) then
				process.exec("chmod", { "-R", "u+w", base })
				fs.removeDir(base)
			end
			for _, d in { "open", "viaenv", "viaconf", "closed" } do
				fs.writeDir(`{base}/{d}`)
			end
			process.exec("chmod", { "555", `{base}/closed` })
			local lookups: { string } = {}
			local found = fence.leaks({
				`{base}/open`,
				"$FIXTURE_ENV",
				"getconf:FIXTURE_CONF",
				`{base}/closed`,
				`{base}/missing`,
				"$FIXTURE_UNSET",
			}, function(name: string): string?
				table.insert(lookups, name)
				if name == "FIXTURE_ENV" then
					return `{base}/viaenv`
				elseif name == "FIXTURE_CONF" then
					return `{base}/viaconf`
				end
				return nil
			end)
			process.exec("chmod", { "755", `{base}/closed` })
			t.expect(#found).toBe(3)
			for _, d in { "open", "viaenv", "viaconf" } do
				local hit = false
				for _, label in found do
					hit = hit or has(label, `{base}/{d}`)
				end
				t.expect(hit).toBe(true)
			end
			t.expect(lookups).toEqual({ "FIXTURE_ENV", "FIXTURE_CONF", "FIXTURE_UNSET" }) -- names without their prefix
			t.expect(#fs.readDir(`{base}/open`)).toBe(0) -- the probe file is gone
			fs.removeDir(base)
		end
	)
end)
