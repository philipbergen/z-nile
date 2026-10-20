--!strict
-- c0075 AC3: the launcher (fence.REAPER) records itself in the run's lock. Inside the Linux jail the guarded processes
-- record nothing (their pids are another namespace's), and the top process can be killed while the jail goes on, so the
-- launcher, which lives in the host namespace exactly as long as the jail, is what keeps the lock held for a second run.
-- Driven directly, as c0079 does: a launcher started here, running a stand-in command that lists the lock.
local fence = require("@tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0075-launcher-lock`

-- the command: writes its parent (the launcher) to ppid.txt and the lock's file names to ls.txt
local SCRIPT = 'echo $PPID > "$1/ppid.txt"; ls "$2" > "$1/ls.txt"'

local function setUp()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(`{base}/lock`)
	fs.writeDir(`{base}/out`)
end

local function launch(env: { [string]: string }, lock: string): (string, string)
	local r = process.exec(
		"perl",
		{ "-e", fence.REAPER, "sh", "-c", SCRIPT, "_", `{base}/out`, lock },
		{ env = env }
	)
	t.expect(r.ok).toBe(true)
	local function read(name: string): string
		return (string.gsub(fs.readFile(`{base}/out/{name}`), "%s+$", ""))
	end
	return read("ppid.txt"), read("ls.txt")
end

return t.spec("c0075 the launcher holds the run's lock", function(it)
	it("records its own pid in the lock while the command runs", function()
		setUp()
		local ppid, ls = launch({ PICKMAN_REAP_LOCK = `{base}/lock` }, `{base}/lock`)
		t.expect(string.match(ppid, "^%d+$") ~= nil).toBe(true)
		t.expect(ls).toBe(`pid-{ppid}`)
	end)

	it("records nothing without the lock variable", function()
		setUp()
		local _, ls = launch({ PICKMAN_REAP_LOCK = "" }, `{base}/lock`)
		t.expect(ls).toBe("")
	end)

	it("records nothing when the lock is not a folder", function()
		setUp()
		fs.removeDir(`{base}/lock`)
		fs.writeFile(`{base}/lock`, "")
		local r = process.exec(
			"perl",
			{ "-e", fence.REAPER, "true" },
			{ env = { PICKMAN_REAP_LOCK = `{base}/lock` } }
		)
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{base}/lock`)).toBe(true)
	end)

	it("never writes through a link: a link in place of the lock is left alone", function()
		setUp()
		fs.writeDir(`{base}/elsewhere`)
		fs.removeDir(`{base}/lock`)
		t.expect(process.exec("ln", { "-s", `{base}/elsewhere`, `{base}/lock` }).ok).toBe(true)
		local r = process.exec(
			"perl",
			{ "-e", fence.REAPER, "true" },
			{ env = { PICKMAN_REAP_LOCK = `{base}/lock` } }
		)
		t.expect(r.ok).toBe(true)
		t.expect(#fs.readDir(`{base}/elsewhere`)).toBe(0)
	end)
end)
