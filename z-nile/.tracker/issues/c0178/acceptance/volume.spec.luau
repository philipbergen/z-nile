--!strict
-- c0178 slice 3 (AC5): the per-run fixture volume's decisions, as pure functions over what `mount` and `diskutil info`
-- print: which mounted volumes are a stale fixture volume of this home (and nothing else is ever detached), how a volume
-- names its owner, and when a run uses a volume at all. The attach, mount and detach themselves are the runner's, proved by
-- check.sh (a real RAM disk, a killed run). Sequestered: it targets z-nile/tests/lib/fxvolume.luau as the Design states it.
local fxvolume = require("@tests/lib/fxvolume")
local t = require("@tests/lib/t")

local CACHE = "/Users/u/code/repo/.worktree/w/z-nile/.cache"
local MOUNT = table.concat({
	"/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)",
	`/dev/disk7s1 on {CACHE} (apfs, local, nodev, nosuid, journaled, noowners, nobrowse, mounted by u)`,
	`/dev/disk9s1 on {CACHE}/inner (apfs, local, nodev, nosuid, journaled, noowners, nobrowse, mounted by u)`,
	`/dev/disk11s1 on {CACHE}2 (apfs, local, nodev, nosuid, journaled, noowners, nobrowse, mounted by u)`,
	"/dev/disk5s1 on /private/var/run/com.apple.security.cryptexd/mnt/x (apfs, sealed, local, read-only, journaled, nobrowse)",
}, "\n")

local function infoFor(names: { [string]: { name: string, protocol: string } })
	return function(point: string): { name: string, protocol: string }?
		return names[point]
	end
end

local OURS = fxvolume.name("4242", "start-id-of-4242")

return t.spec("c0178 the per-run fixture volume", function(it)
	it("reads every mount line's device and mount point, spaces in the path included", function()
		local m =
			fxvolume.parseMounts(MOUNT .. "\n/dev/disk12s1 on /Users/u/a b/.cache (apfs, local, nobrowse)")
		t.expect(#m).toBe(6)
		t.expect(m[2].device).toBe("/dev/disk7s1")
		t.expect(m[2].point).toBe(CACHE)
		t.expect(m[6].point).toBe("/Users/u/a b/.cache")
	end)

	it("a volume names its owner, and the owner is read back from the name", function()
		t.expect(string.sub(OURS, 1, #fxvolume.PREFIX)).toBe(fxvolume.PREFIX)
		local pid, start = fxvolume.owner(OURS)
		t.expect(pid).toBe("4242")
		t.expect(start).toBe(fxvolume.startKey("start-id-of-4242"))
		t.expect(#OURS <= 63).toBe(true)
		t.expect(fxvolume.owner("Macintosh HD")).toBe(nil)
	end)

	it(
		"lists a fixture volume of a dead owner mounted exactly at this home's .cache, and nothing else",
		function()
			local info = infoFor({
				[CACHE] = { name = OURS, protocol = "Disk Image" },
				[`{CACHE}/inner`] = { name = OURS, protocol = "Disk Image" },
				[`{CACHE}2`] = { name = OURS, protocol = "Disk Image" },
			})
			local dead = function(_pid: string, _start: string): boolean
				return false
			end
			local got = fxvolume.stale(fxvolume.parseMounts(MOUNT), info, CACHE, dead)
			t.expect(table.concat(got, ",")).toBe("/dev/disk7s1")
		end
	)

	it(
		"never lists a live owner's volume, another program's volume or a real disk at the same place",
		function()
			local alive = function(pid: string, _start: string): boolean
				return pid == "4242"
			end
			local dead = function(_pid: string, _start: string): boolean
				return false
			end
			local mounts = fxvolume.parseMounts(MOUNT)
			t.expect(
				#fxvolume.stale(
					mounts,
					infoFor({ [CACHE] = { name = OURS, protocol = "Disk Image" } }),
					CACHE,
					alive
				)
			).toBe(0)
			t.expect(
				#fxvolume.stale(
					mounts,
					infoFor({ [CACHE] = { name = "RAMDisk", protocol = "Disk Image" } }),
					CACHE,
					dead
				)
			).toBe(0)
			t.expect(
				#fxvolume.stale(mounts, infoFor({ [CACHE] = { name = OURS, protocol = "USB" } }), CACHE, dead)
			)
				.toBe(0)
			t.expect(#fxvolume.stale(mounts, infoFor({}), CACHE, dead)).toBe(0)
		end
	)

	it("a run uses a volume only on macOS, as the outermost run, when the gate asked for one", function()
		local yes, why = fxvolume.wanted({ PICKMAN_FIXTURE_VOLUME = "1" }, "macos", false)
		t.expect(yes).toBe(true)
		t.expect(why).toBe("")
		local function no(env: { [string]: string }, os: string, guarded: boolean, reason: string)
			local used, said = fxvolume.wanted(env, os, guarded)
			t.expect(used).toBe(false)
			t.expect(string.find(said, reason, 1, true) ~= nil).toBe(true)
		end
		no({ PICKMAN_FIXTURE_VOLUME = "1" }, "linux", false, "linux")
		no({ PICKMAN_FIXTURE_VOLUME = "1" }, "macos", true, "nested")
		no({}, "macos", false, "not asked")
		no({ PICKMAN_FIXTURE_VOLUME = "0" }, "macos", false, "not asked")
	end)
end)
