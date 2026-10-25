--!strict
-- c0720: tests/lib/cleanup.luau removes a fixture tree, retrying for a bounded time while something still writes into
-- it, and fails with what is left. Races are made deterministic through the `remove` seam (no shell writer: R0210's
-- testing rule bans shell strings in specs). Fixture under .cache/c0720-cleanup.
local cleanup = require("@tests/lib/cleanup")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

-- c0120 override: a spec writes only under its home's .cache (the jail refuses the checkout top's)
local base = `{process.cwd}.cache/c0720-cleanup`

local function tree(name: string): string
	local dir = `{base}/{name}`
	fs.writeDir(`{dir}/a/b`)
	for i = 1, 20 do
		fs.writeFile(`{dir}/a/b/f{i}.txt`, "x")
	end
	fs.writeFile(`{dir}/top.txt`, "x")
	return dir
end

return t.spec("cleanup.removeTree", function(it)
	it("sets up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
	end)

	it("removes a tree and succeeds for a missing path", function()
		local dir = tree("plain")
		cleanup.removeTree(dir)
		t.expect(fs.isDir(dir)).toBe(false)
		cleanup.removeTree(`{base}/never-made`) -- no error
	end)

	it("retries a remover that races, then succeeds", function()
		local dir = tree("flaky")
		local calls = 0
		cleanup.removeTree(dir, 3, function(path: string)
			calls += 1
			if calls < 3 then
				error(`Directory not empty (os error 66): {path}`)
			end
			fs.removeDir(path)
		end)
		t.expect(calls).toBe(3)
		t.expect(fs.isDir(dir)).toBe(false)
	end)

	it("retries at least once even when the first attempt outlasts the bound", function()
		local dir = tree("slow")
		local calls = 0
		local ok = pcall(cleanup.removeTree, dir, 0.05, function(path: string)
			calls += 1
			task.wait(0.1) -- the first attempt alone spends the whole bound
			error(`Directory not empty (os error 66): {path}`)
		end)
		t.expect(ok).toBe(false)
		t.expect(calls >= 2).toBe(true)
		fs.removeDir(dir)
	end)

	it("gives up after its bound and lists what is left", function()
		local dir = tree("stuck")
		local calls = 0
		local ok, err = pcall(cleanup.removeTree, dir, 0.3, function(path: string)
			calls += 1
			error(`Directory not empty (os error 66): {path}`)
		end)
		t.expect(ok).toBe(false)
		local msg = tostring(err)
		t.expect(string.find(msg, "could not remove", 1, true) ~= nil).toBe(true)
		t.expect(string.find(msg, "top.txt", 1, true) ~= nil).toBe(true)
		t.expect(calls >= 2).toBe(true)
		t.expect(calls <= 12).toBe(true) -- 50 ms apart within 0.3 s, not a busy loop
		fs.removeDir(dir)
	end)

	it("raises an error that is not a race at once", function()
		local dir = tree("denied")
		local calls = 0
		local ok, err = pcall(cleanup.removeTree, dir, 3, function(_path: string)
			calls += 1
			error("Permission denied (os error 13)")
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "Permission denied", 1, true) ~= nil).toBe(true)
		t.expect(calls).toBe(1)
		fs.removeDir(dir)
	end)

	it("cleans up", function()
		cleanup.removeTree(base)
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
