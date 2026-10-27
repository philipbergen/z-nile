--!strict
-- c0144 AC3 (run by check.sh only, never promoted to a gate rule: not a *.spec.luau): piped, every command with a look
-- prints byte for byte what the engine before c0144 printed, in the same fixture. check.sh unpacks that engine (the
-- merge base with origin/main: zn, z-nile/engine and z-nile/lib) under .cache and names it in C0144_BASE; this file
-- runs the commands with the branch's tooling, then swaps the base's tooling into the fixture and runs them again.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seed = require("./seed")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local BASE = process.env.C0144_BASE

-- copies `from` over `to`, file by file (both under .cache)
local function copyTree(from: string, to: string)
	for _, name in fs.readDir(from) do
		local a, b = `{from}/{name}`, `{to}/{name}`
		if fs.isDir(a) then
			if not fs.isDir(b) then
				fs.writeDir(b)
			end
			copyTree(a, b)
		else
			fs.writeFile(b, fs.readFile(a))
		end
	end
end

return t.spec("c0144 piped output is the engine's before c0144, byte for byte", function(it)
	it(
		"runs every command with the branch's tooling and with the base's, and the outputs are equal",
		function()
			-- fails closed: without the base there is nothing to compare, which is not "equal"
			t.expect(BASE ~= nil and BASE ~= "" and fs.isDir(`{BASE}/z-nile/engine`)).toBe(true)
			local f = seed.build("c0144-plain-base")
			local now: { { [string]: any } } = {}
			for _, args in seed.COMMANDS do
				local r = trackerfix.tr(f, f.main, args)
				table.insert(now, { args = args, out = r.stdout, err = r.stderr, code = r.code })
			end
			local usage = trackerfix.tr(f, f.main, {})
			table.insert(now, { args = {}, out = usage.stdout, err = usage.stderr, code = usage.code })
			-- the base's engine, library and command, over the fixture's copies
			fs.writeFile(`{f.main}/zn`, fs.readFile(`{BASE :: string}/zn`))
			copyTree(`{BASE :: string}/z-nile/engine`, `{f.main}/z-nile/engine`)
			copyTree(`{BASE :: string}/z-nile/lib`, `{f.main}/z-nile/lib`)
			for _, gone in { "term.luau", "look.luau" } do
				if
					fs.isFile(`{f.main}/z-nile/engine/{gone}`)
					and not fs.isFile(`{BASE :: string}/z-nile/engine/{gone}`)
				then
					fs.removeFile(`{f.main}/z-nile/engine/{gone}`)
				end
			end
			fixture.git(f.main, { "commit", "-qam", "the base's tooling" })
			for i, args in seed.COMMANDS do
				local r = trackerfix.tr(f, f.main, args)
				t.expect(now[i]).toEqual({ args = args, out = r.stdout, err = r.stderr, code = r.code })
			end
			-- the usage text gained one paragraph (the --color options) and is otherwise the base's
			local before = trackerfix.tr(f, f.main, {})
			local last = now[#now]
			t.expect(string.sub(last.out, 1, #before.stdout - 1)).toBe(string.sub(before.stdout, 1, -2))
			t.expect(
				string.find(string.sub(last.out, #before.stdout), "--color=auto|always|never", 1, true) ~= nil
			)
				.toBe(true)
			fs.removeDir(f.base)
		end
	)
end)
