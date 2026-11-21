--!strict
-- R0138 review 002 F2: a rerun that does not fit the net's own time (`--limit 1` stands for a long round) is handed to a
-- fresh net with its own time, which runs it exactly once; the ending net says where it went. A hand-off whose fresh net
-- cannot start ends the handing-off net with exit 1 (review 003 F2).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local t = require("@tests/lib/t")
local watch = require("@znile/lib/watch")

local has, read, trim = netfix.has, netfix.read, netfix.trim

local function runs(w: netfix.World): string
	return string.gsub(trim(read(`{w.hold}/runs`)), "\n", " ") :: string
end

return t.spec("a rerun that does not fit goes to a fresh net", function(it)
	it("the ending net starts a fresh net for the request, and the request runs once", function()
		local l = netfix.world("r0138-limit", { standing = true })
		netfix.holdOn(l)
		local files = watch.filesDir(l.main)
		local one = netfix.kick(l, l.raft, { "--limit", "1" })
		t.expect(one.code).toBe(0)
		local log = netfix.logOf(one.stdout) :: string
		t.expect(netfix.waitFor(`{l.hold}/started`)).toBe(true)
		t.expect(netfix.kick(l, l.f.main).code).toBe(0)
		fs.writeFile(`{l.hold}/release`, "go\n")
		t.expect(netfix.settle(log)).toBe("0")
		-- the first net says where the rerun went, and does not run it itself
		t.expect(has(read(log), "the rerun goes to a fresh net")).toBe(true)
		t.expect(has(read(log), "running again")).toBe(false)
		local second = netfix.logOf(read(log)) :: string
		t.expect(second ~= log).toBe(true)
		-- the fresh net starts after the first has ended: under a loaded gate it can take longer than one wait
		local code = ""
		for _ = 1, 4 do
			code = netfix.settle(second)
			if code ~= "" then
				break
			end
		end
		t.expect(code).toBe("0")
		-- the request was run exactly once, by the second net, and nothing is left
		t.expect(runs(l)).toBe("start end start end")
		t.expect(fs.isFile(`{files}/rerun`)).toBe(false)
		t.expect(fs.isFile(`{files}/lock`)).toBe(false)
	end)

	it(
		"a hand-off whose fresh net cannot start ends the handing-off net with exit 1 and the reason",
		function()
			local f = netfix.world("r0138-handoff-fail", { standing = true })
			netfix.holdOn(f)
			local files = watch.filesDir(f.main)
			local one = netfix.kick(f, f.raft, { "--limit", "1" })
			t.expect(one.code).toBe(0)
			local log = netfix.logOf(one.stdout) :: string
			t.expect(netfix.waitFor(`{f.hold}/started`)).toBe(true)
			t.expect(netfix.kick(f, f.f.main).code).toBe(0)
			-- origin goes away under the held suite: the fresh net's first fetch fails, the first net needs origin no more
			fixture.git(f.f.main, { "remote", "set-url", "origin", `{f.base}/no-such-origin.git` })
			fs.writeFile(`{f.hold}/release`, "go\n")
			t.expect(netfix.settle(log)).toBe("1")
			t.expect(has(read(log), "the rerun could not be handed to a fresh net")).toBe(true)
			t.expect(has(read(log), "git fetch origin main failed")).toBe(true)
			t.expect(has(read(log), "the next landing's kick runs it")).toBe(true)
			t.expect(fs.isFile(`{files}/lock`)).toBe(false)
			t.expect(runs(f)).toBe("start end")
		end
	)
end)
